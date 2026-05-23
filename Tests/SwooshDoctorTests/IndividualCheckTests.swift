// Tests/SwooshDoctorTests/IndividualCheckTests.swift — 0.9B
//
// Happy + failure path coverage per built-in `DoctorCheck` that can be
// driven from a sandboxed temp directory. Checks that read shared host
// state (Keychain access, real network reachability, real `~/.swoosh`
// size) are covered by the existing smoke tests and not duplicated here.
//
// Each test runs against its own temp-rooted `DoctorContext` so the
// tests are hermetic and don't depend on the developer's actual config.

import Foundation
import XCTest
@testable import SwooshDoctor

private func makeTempRoot(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("swoosh-doctor-\(label)-\(UUID().uuidString)", isDirectory: true)
}

private func makeContext(root: URL) -> DoctorContext {
    DoctorContext(
        configPath: root.appendingPathComponent("config.json").path,
        statePath: root.path,
        logPath: root.appendingPathComponent("logs").path
    )
}

// MARK: - ConfigFileCheck

final class ConfigFileCheckTests: XCTestCase {

    func testWarnsWhenConfigMissing() async throws {
        let root = makeTempRoot("config-missing")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let result = try await ConfigFileCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .warning)
        XCTAssertEqual(result.fixCommand, "swoosh setup")
    }

    func testPassesWhenConfigPresent() async throws {
        let root = makeTempRoot("config-present")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent("config.json")
        try #"{"model":"gpt-4o"}"#.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try await ConfigFileCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .pass)
        XCTAssertNil(result.fixCommand)
    }
}

// MARK: - ModelConfigCheck

final class ModelConfigCheckTests: XCTestCase {

    func testWarnsWhenNoConfig() async throws {
        let root = makeTempRoot("model-no-config")
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await ModelConfigCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .warning)
        XCTAssertEqual(result.fixCommand, "swoosh setup")
    }

    func testPassesWhenModelKeyPresent() async throws {
        let root = makeTempRoot("model-present")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent("config.json")
        try "model: gpt-4o\n".write(to: configURL, atomically: true, encoding: .utf8)

        let result = try await ModelConfigCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .pass)
    }

    func testWarnsWhenConfigLacksModelKey() async throws {
        let root = makeTempRoot("model-missing-key")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent("config.json")
        // Free-form text with no `model:`, `provider:`, `"modelPath"`,
        // and not a valid SwooshRuntimeConfig — must be flagged.
        try "some_unrelated_setting: true\n".write(to: configURL, atomically: true, encoding: .utf8)

        let result = try await ModelConfigCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .warning)
    }
}

// MARK: - TokenBudgetCheck

final class TokenBudgetCheckTests: XCTestCase {

    func testWarnsWithoutConfigFile() async throws {
        let root = makeTempRoot("budget-no-config")
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await TokenBudgetCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .warning)
        XCTAssertEqual(result.fixCommand, "swoosh config set budget.daily_limit 25")
    }

    func testPassesWithBudgetKey() async throws {
        let root = makeTempRoot("budget-present")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent("config.json")
        try "budget: daily=25\n".write(to: configURL, atomically: true, encoding: .utf8)

        let result = try await TokenBudgetCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .pass)
    }

    func testWarnsWithUnrelatedConfig() async throws {
        let root = makeTempRoot("budget-unrelated")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent("config.json")
        try "profile: developer\n".write(to: configURL, atomically: true, encoding: .utf8)

        let result = try await TokenBudgetCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .warning)
    }
}

// MARK: - LogPrivacyCheck

final class LogPrivacyCheckTests: XCTestCase {

    func testPassesWhenLogsDirMissing() async throws {
        let root = makeTempRoot("log-no-dir")
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await LogPrivacyCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .pass)
    }

    func testPassesWhenLogsAreClean() async throws {
        let root = makeTempRoot("log-clean")
        defer { try? FileManager.default.removeItem(at: root) }
        let logsDir = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try "Hello world, nothing sensitive here.".write(
            to: logsDir.appendingPathComponent("app.log"), atomically: true, encoding: .utf8
        )
        let result = try await LogPrivacyCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .pass)
    }

    func testWarnsWhenSecretInLog() async throws {
        let root = makeTempRoot("log-secret")
        defer { try? FileManager.default.removeItem(at: root) }
        let logsDir = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try "request: Bearer sk_live_real_secret_here".write(
            to: logsDir.appendingPathComponent("app.log"), atomically: true, encoding: .utf8
        )
        let result = try await LogPrivacyCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .warning)
        XCTAssertEqual(result.fixCommand, "swoosh logs redact")
    }
}

// MARK: - LocalModelCheck

final class LocalModelCheckTests: XCTestCase {

    // The check reads `~/.swoosh/models` directly (not from context),
    // so we can only assert it returns a pass result — either "no
    // directory" or "N models". The status is always .pass for this
    // check; that's the contract.
    func testAlwaysPasses() async throws {
        let root = makeTempRoot("local-model")
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await LocalModelCheck().run(context: makeContext(root: root))
        XCTAssertEqual(result.status, .pass)
    }
}

// MARK: - PrivacyScanner single-pass behaviour

final class PrivacyScannerSinglePassTests: XCTestCase {

    func testFlagsLightUpForAllThreeFamilies() {
        let scanner = PrivacyScanner()
        // Contains one match for each family (the secret family lists
        // multiple patterns, so don't assert an exact issue count here —
        // assert the per-family booleans, which is what the refactor
        // was about).
        let result = scanner.scanText("password=hunter2 cookie: y mnemonic: z")
        XCTAssertTrue(result.hasSecrets)
        XCTAssertTrue(result.hasCookies)
        XCTAssertTrue(result.hasSeedPhrases)
        XCTAssertFalse(result.isClean)
    }

    func testIssueCountEqualsMatchedPatternCount() {
        let scanner = PrivacyScanner()
        // "api_key=" and "sk_live_" both belong to the secrets family;
        // the single-pass scan should record one issue per matched
        // pattern (not per family).
        let result = scanner.scanText("api_key=sk_live_x cookie: y mnemonic: z")
        XCTAssertEqual(result.issues.count, 4, "expected 1×api_key + 1×sk_live + 1×cookie + 1×mnemonic")
    }

    func testFlagsAgreeWithIssuesList() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("just a secret: api_key=foo")
        // Flag and issues must agree — the single-pass refactor was
        // motivated by the prior double-scan being able to disagree.
        XCTAssertEqual(result.hasSecrets, result.issues.contains { $0.hasPrefix("Secret") })
        XCTAssertFalse(result.hasCookies)
        XCTAssertFalse(result.hasSeedPhrases)
    }

    func testCleanInputProducesEmptyIssues() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("nothing here but ordinary words")
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertTrue(result.isClean)
    }
}

// MARK: - Optimization recommendations use DoctorCheckID

final class OptimizationRecommendationsTests: XCTestCase {

    func testRecommendsCredentialDiscoveryWhenProviderKeysNotPassing() {
        let report = DoctorReport(checks: [
            DoctorCheckResult(checkID: DoctorCheckID.providerKeys, title: "Keys",
                              category: .secrets, status: .warning,
                              message: "no env keys",
                              fixCommand: "swoosh discover-credentials"),
        ])
        XCTAssertTrue(report.optimizationRecommendations.contains {
            $0.contains("discover-credentials")
        })
    }

    func testRecommendsRestartOnMemoryWarning() {
        let report = DoctorReport(checks: [
            DoctorCheckResult(checkID: DoctorCheckID.memory, title: "Memory",
                              category: .installation, status: .warning,
                              message: "high"),
        ])
        XCTAssertTrue(report.optimizationRecommendations.contains {
            $0.contains("Restart Swoosh")
        })
    }

    func testNoRestartRecommendationWhenMemoryPasses() {
        let report = DoctorReport(checks: [
            DoctorCheckResult(checkID: DoctorCheckID.memory, title: "Memory",
                              category: .installation, status: .pass),
        ])
        XCTAssertFalse(report.optimizationRecommendations.contains {
            $0.contains("Restart Swoosh")
        })
    }
}
