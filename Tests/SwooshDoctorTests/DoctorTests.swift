// Tests/SwooshDoctorTests/DoctorTests.swift — 0.9A

import Foundation
import XCTest
import SwooshConfig
@testable import SwooshDoctor
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Doctor Report Tests
// ═══════════════════════════════════════════════════════════════

final class DoctorReportTests: XCTestCase {

    func testHealthyReport() {
        let report = DoctorReport(checks: [
            DoctorCheckResult(checkID: "app_installed", title: "Swoosh.app installed", category: .installation, status: .pass),
            DoctorCheckResult(checkID: "cli_installed", title: "CLI installed", category: .installation, status: .pass),
            DoctorCheckResult(checkID: "daemon_running", title: "Daemon running", category: .daemon, status: .pass),
        ])
        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.summary.passed, 3)
        XCTAssertEqual(report.summary.failures, 0)
    }

    func testUnhealthyReport() {
        let report = DoctorReport(checks: [
            DoctorCheckResult(checkID: "model_test", title: "Model test", category: .model,
                              status: .fail, message: "No provider", fixCommand: "swoosh model test"),
        ])
        XCTAssertFalse(report.isHealthy)
        XCTAssertEqual(report.summary.failures, 1)
    }

    func testReportWarnings() {
        let report = DoctorReport(checks: [
            DoctorCheckResult(checkID: "secret_check", title: "Keychain", category: .secrets, status: .warning, message: "Key missing"),
        ])
        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.summary.warnings, 1)
    }

    func testFixCommand() {
        let result = DoctorCheckResult(
            checkID: "model_test", title: "Model test", category: .model,
            status: .fail, fixCommand: "swoosh model test"
        )
        XCTAssertEqual(result.fixCommand, "swoosh model test")
    }

    func testAllCategories() {
        XCTAssertEqual(DoctorCategory.allCases.count, 13)
    }

    func testSwooshDirectoryCheckUsesContextPath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-doctor-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let missing = try await SwooshDirCheck().run(context: DoctorContext(
            configPath: root.appendingPathComponent("config.json").path,
            statePath: root.path,
            logPath: root.appendingPathComponent("logs").path
        ))
        XCTAssertEqual(missing.status, .fail)

        for directory in [
            "memories",
            "skills",
            "workflows",
            "goals",
            "manifesting",
            "scout",
            "cron",
            "logs",
            "artifacts",
            "mcp",
            "workers",
            "setup-reports",
            "models",
            "checkpoints",
        ] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let repaired = try await SwooshDirCheck().run(context: DoctorContext(
            configPath: root.appendingPathComponent("config.json").path,
            statePath: root.path,
            logPath: root.appendingPathComponent("logs").path
        ))
        XCTAssertEqual(repaired.status, .pass)
    }

    func testRuntimeReadinessUsesSharedConfigState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-readiness-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let config = SwooshConfigStore(configDirectory: root)
        let missing = SwooshReadinessDetector(config: config).report()
        XCTAssertEqual(missing.state, .blocked)
        XCTAssertEqual(missing.component(id: "config.file")?.status, .blocked)

        try config.ensureDirectories()
        try config.save(SwooshRuntimeConfig(
            setupMode: "quick",
            permissionProfile: "developer",
            modelPath: "hybrid",
            daemonPort: 1
        ))
        try "token".write(to: config.apiTokenFile, atomically: true, encoding: .utf8)

        let readyLocal = SwooshReadinessDetector(config: config).report(inputs: SwooshReadinessInputs(
            daemonReachable: true,
            chatEnabled: true,
            activeProviderName: "Local Diagnostic Provider",
            activeModel: "swoosh-local-diagnostic-v1",
            promptableSkillCount: 1
        ))
        XCTAssertEqual(readyLocal.state, .ready)
        XCTAssertEqual(readyLocal.component(id: "model.provider")?.status, .ready)
    }

    func testAutonomousRuntimeConfigDerivesUnrestrictedPolicy() throws {
        let config = SwooshRuntimeConfig(
            setupMode: "quick",
            permissionProfile: "autonomous",
            modelPath: "hybrid"
        )
        XCTAssertEqual(config.toolPolicy, .autonomous)
        XCTAssertEqual(config.safetyConfig, .autonomous)
        XCTAssertEqual(PermissionProfilePreset.autonomous.grantedSwooshPermissions.count, SwooshPermission.allCases.count)
    }

    func testRuntimeReadinessDoctorCheckMapsSharedState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-readiness-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let config = SwooshConfigStore(configDirectory: root)
        try config.ensureDirectories()
        try config.save(SwooshRuntimeConfig(
            setupMode: "quick",
            permissionProfile: "developer",
            modelPath: "hybrid",
            daemonPort: 1
        ))
        try "token".write(to: config.apiTokenFile, atomically: true, encoding: .utf8)

        let result = try await RuntimeReadinessCheck().run(context: DoctorContext(
            configPath: config.configFile.path,
            statePath: root.path,
            logPath: config.logsDir.path
        ))
        XCTAssertEqual(result.status, .warning)
        XCTAssertTrue(result.message?.contains("Degraded") == true)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Privacy Report Tests
// ═══════════════════════════════════════════════════════════════

final class PrivacyReportTests: XCTestCase {

    func testCleanReport() {
        let report = PrivacyReport(approvedMemoryCount: 5, pendingMemoryCandidateCount: 2)
        XCTAssertTrue(report.isClean)
        XCTAssertFalse(report.cookieLikeDataFound)
        XCTAssertFalse(report.rawTokensFoundInConfig)
    }

    func testCookiesFound() {
        let report = PrivacyReport(cookieLikeDataFound: true)
        XCTAssertFalse(report.isClean)
    }

    func testTokensInConfig() {
        let report = PrivacyReport(rawTokensFoundInConfig: true)
        XCTAssertFalse(report.isClean)
    }

    func testPrivateKeysFound() {
        let report = PrivacyReport(privateKeysFound: true)
        XCTAssertFalse(report.isClean)
    }

    func testSeedPhrasesFound() {
        let report = PrivacyReport(seedPhrasesFound: true)
        XCTAssertFalse(report.isClean)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Privacy Scanner Tests
// ═══════════════════════════════════════════════════════════════

final class PrivacyScannerTests: XCTestCase {

    func testDetectsPrivateKeys() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("found -----BEGIN PRIVATE KEY in file")
        XCTAssertTrue(result.hasSecrets)
        XCTAssertFalse(result.isClean)
    }

    func testDetectsCookies() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("cookie: session=abc123")
        XCTAssertTrue(result.hasCookies)
        XCTAssertFalse(result.isClean)
    }

    func testDetectsSeedPhrases() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("mnemonic: word1 word2 word3")
        XCTAssertTrue(result.hasSeedPhrases)
        XCTAssertFalse(result.isClean)
    }

    func testDetectsAPIKeys() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("api_key=sk_live_12345")
        XCTAssertTrue(result.hasSecrets)
    }

    func testDetectsBearerTokens() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("Authorization: Bearer eyJhbGc...")
        XCTAssertTrue(result.hasSecrets)
    }

    func testCleanTextPasses() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("Hello, this is a normal log message about Swift compilation.")
        XCTAssertTrue(result.isClean)
    }

    func testIssuesPopulated() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("found sk_live_123 and cookie: session=abc")
        XCTAssertGreaterThanOrEqual(result.issues.count, 2)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Debug Bundle Tests
// ═══════════════════════════════════════════════════════════════

final class DebugBundleTests: XCTestCase {

    func testContainsDoctorReport() {
        let doctorReport = DoctorReport(checks: [
            DoctorCheckResult(checkID: "test", title: "Test", category: .config, status: .pass),
        ])
        let bundle = DebugBundle(doctorReport: doctorReport, privacyReport: PrivacyReport(),
                                 redactedConfig: "model: test")
        XCTAssertTrue(bundle.doctorReport.isHealthy)
    }

    func testContainsPrivacyReport() {
        let bundle = DebugBundle(doctorReport: DoctorReport(checks: []),
                                 privacyReport: PrivacyReport(),
                                 redactedConfig: "")
        XCTAssertTrue(bundle.privacyReport.isClean)
    }

    func testConfigRedacted() {
        let redactor = DebugBundleRedactor()
        let raw = """
        model: gpt-4
        api_key: sk_live_12345
        token: abc123
        password: hunter2
        """
        let redacted = redactor.redactConfig(raw)
        XCTAssertFalse(redacted.contains("sk_live_12345"))
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertTrue(redacted.contains("[REDACTED]"))
    }

    func testRedactorPreservesSafe() {
        let redactor = DebugBundleRedactor()
        let raw = "model: gpt-4\nprofile: developer"
        let redacted = redactor.redactConfig(raw)
        XCTAssertTrue(redacted.contains("model: gpt-4"))
        XCTAssertTrue(redacted.contains("profile: developer"))
    }

    func testRedactorCatchesPrivateKeys() {
        let redactor = DebugBundleRedactor()
        let raw = "cert: -----BEGIN PRIVATE KEY data"
        let redacted = redactor.redactConfig(raw)
        XCTAssertFalse(redacted.contains("-----BEGIN"))
    }

    func testRedactorCatchesSeed() {
        let redactor = DebugBundleRedactor()
        let raw = "backup: mnemonic word1 word2"
        let redacted = redactor.redactConfig(raw)
        XCTAssertFalse(redacted.contains("mnemonic"))
    }

    func testBundleNoRawSecrets() {
        let redactor = DebugBundleRedactor()
        let redactedConfig = redactor.redactConfig("api_key: sk_live_real_key\ntoken: real_token")
        let bundle = DebugBundle(
            doctorReport: DoctorReport(checks: []),
            privacyReport: PrivacyReport(),
            redactedConfig: redactedConfig
        )
        XCTAssertFalse(bundle.redactedConfig.contains("sk_live_real_key"))
        XCTAssertFalse(bundle.redactedConfig.contains("real_token"))
    }
}
