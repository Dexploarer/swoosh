// Tests/SwooshDoctorTests/DoctorTests.swift — 0.9A

import Testing
import Foundation
@testable import SwooshDoctor
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Doctor Report Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Doctor Report")
struct DoctorReportTests {

    @Test("Healthy report with all passing")
    func healthyReport() {
        let report = DoctorReport(checks: [
            DoctorCheckResult(checkID: "app_installed", title: "Swoosh.app installed", category: .installation, status: .pass),
            DoctorCheckResult(checkID: "cli_installed", title: "CLI installed", category: .installation, status: .pass),
            DoctorCheckResult(checkID: "daemon_running", title: "Daemon running", category: .daemon, status: .pass),
        ])
        #expect(report.isHealthy)
        #expect(report.summary.passed == 3)
        #expect(report.summary.failures == 0)
    }

    @Test("Unhealthy report with failures")
    func unhealthyReport() {
        let report = DoctorReport(checks: [
            DoctorCheckResult(checkID: "model_test", title: "Model test", category: .model,
                              status: .fail, message: "No provider", fixCommand: "swoosh model test"),
        ])
        #expect(!report.isHealthy)
        #expect(report.summary.failures == 1)
    }

    @Test("Report with warnings")
    func reportWarnings() {
        let report = DoctorReport(checks: [
            DoctorCheckResult(checkID: "secret_check", title: "Keychain", category: .secrets, status: .warning, message: "Key missing"),
        ])
        #expect(report.isHealthy) // warnings don't fail
        #expect(report.summary.warnings == 1)
    }

    @Test("Fix command present on failures")
    func fixCommand() {
        let result = DoctorCheckResult(
            checkID: "model_test", title: "Model test", category: .model,
            status: .fail, fixCommand: "swoosh model test"
        )
        #expect(result.fixCommand == "swoosh model test")
    }

    @Test("All categories available")
    func allCategories() {
        #expect(DoctorCategory.allCases.count == 13)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Privacy Report Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Privacy Report")
struct PrivacyReportTests {

    @Test("Clean privacy report")
    func cleanReport() {
        let report = PrivacyReport(approvedMemoryCount: 5, pendingMemoryCandidateCount: 2)
        #expect(report.isClean)
        #expect(!report.cookieLikeDataFound)
        #expect(!report.rawTokensFoundInConfig)
    }

    @Test("Unclean report — cookies found")
    func cookiesFound() {
        let report = PrivacyReport(cookieLikeDataFound: true)
        #expect(!report.isClean)
    }

    @Test("Unclean report — tokens in config")
    func tokensInConfig() {
        let report = PrivacyReport(rawTokensFoundInConfig: true)
        #expect(!report.isClean)
    }

    @Test("Unclean report — private keys found")
    func privateKeysFound() {
        let report = PrivacyReport(privateKeysFound: true)
        #expect(!report.isClean)
    }

    @Test("Unclean report — seed phrases found")
    func seedPhrasesFound() {
        let report = PrivacyReport(seedPhrasesFound: true)
        #expect(!report.isClean)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Privacy Scanner Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Privacy Scanner")
struct PrivacyScannerTests {

    @Test("Detects private keys")
    func detectsPrivateKeys() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("found -----BEGIN PRIVATE KEY in file")
        #expect(result.hasSecrets)
        #expect(!result.isClean)
    }

    @Test("Detects cookies")
    func detectsCookies() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("cookie: session=abc123")
        #expect(result.hasCookies)
        #expect(!result.isClean)
    }

    @Test("Detects seed phrases")
    func detectsSeedPhrases() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("mnemonic: word1 word2 word3")
        #expect(result.hasSeedPhrases)
        #expect(!result.isClean)
    }

    @Test("Detects API keys")
    func detectsAPIKeys() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("api_key=sk_live_12345")
        #expect(result.hasSecrets)
    }

    @Test("Detects Bearer tokens")
    func detectsBearerTokens() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("Authorization: Bearer eyJhbGc...")
        #expect(result.hasSecrets)
    }

    @Test("Clean text passes")
    func cleanTextPasses() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("Hello, this is a normal log message about Swift compilation.")
        #expect(result.isClean)
    }

    @Test("Issues list populated")
    func issuesPopulated() {
        let scanner = PrivacyScanner()
        let result = scanner.scanText("found sk_live_123 and cookie: session=abc")
        #expect(result.issues.count >= 2)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Debug Bundle Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Debug Bundle")
struct DebugBundleTests {

    @Test("Bundle contains doctor report")
    func containsDoctorReport() {
        let doctorReport = DoctorReport(checks: [
            DoctorCheckResult(checkID: "test", title: "Test", category: .config, status: .pass),
        ])
        let bundle = DebugBundle(doctorReport: doctorReport, privacyReport: PrivacyReport(),
                                 redactedConfig: "model: test")
        #expect(bundle.doctorReport.isHealthy)
    }

    @Test("Bundle contains privacy report")
    func containsPrivacyReport() {
        let bundle = DebugBundle(doctorReport: DoctorReport(checks: []),
                                 privacyReport: PrivacyReport(),
                                 redactedConfig: "")
        #expect(bundle.privacyReport.isClean)
    }

    @Test("Config is redacted in bundle")
    func configRedacted() {
        let redactor = DebugBundleRedactor()
        let raw = """
        model: gpt-4
        api_key: sk_live_12345
        token: abc123
        password: hunter2
        """
        let redacted = redactor.redactConfig(raw)
        #expect(!redacted.contains("sk_live_12345"))
        #expect(!redacted.contains("abc123"))
        #expect(!redacted.contains("hunter2"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Redactor preserves safe lines")
    func redactorPreservesSafe() {
        let redactor = DebugBundleRedactor()
        let raw = "model: gpt-4\nprofile: developer"
        let redacted = redactor.redactConfig(raw)
        #expect(redacted.contains("model: gpt-4"))
        #expect(redacted.contains("profile: developer"))
    }

    @Test("Redactor catches private keys")
    func redactorCatchesPrivateKeys() {
        let redactor = DebugBundleRedactor()
        let raw = "cert: -----BEGIN PRIVATE KEY data"
        let redacted = redactor.redactConfig(raw)
        #expect(!redacted.contains("-----BEGIN"))
    }

    @Test("Redactor catches seed phrases")
    func redactorCatchesSeed() {
        let redactor = DebugBundleRedactor()
        let raw = "backup: mnemonic word1 word2"
        let redacted = redactor.redactConfig(raw)
        #expect(!redacted.contains("mnemonic"))
    }

    @Test("Bundle does not contain raw secrets")
    func bundleNoRawSecrets() {
        let redactor = DebugBundleRedactor()
        let redactedConfig = redactor.redactConfig("api_key: sk_live_real_key\ntoken: real_token")
        let bundle = DebugBundle(
            doctorReport: DoctorReport(checks: []),
            privacyReport: PrivacyReport(),
            redactedConfig: redactedConfig
        )
        #expect(!bundle.redactedConfig.contains("sk_live_real_key"))
        #expect(!bundle.redactedConfig.contains("real_token"))
    }
}
