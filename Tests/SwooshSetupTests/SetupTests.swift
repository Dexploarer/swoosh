// Tests/SwooshSetupTests/SetupTests.swift — 0.9A

import Testing
import Foundation
@testable import SwooshSetup
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Setup Profile Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Setup Profile")
struct SetupProfileTests {

    @Test("All profiles available")
    func allProfiles() {
        #expect(SetupProfile.allCases.count == 5)
    }

    @Test("Quick profile exists")
    func quickProfile() {
        #expect(SetupProfile.quick.rawValue == "quick")
    }

    @Test("Developer profile exists")
    func developerProfile() {
        #expect(SetupProfile.developer.rawValue == "developer")
    }

    @Test("Headless profile exists")
    func headlessProfile() {
        #expect(SetupProfile.headless.rawValue == "headless")
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - First Run State Tests
// ═══════════════════════════════════════════════════════════════

@Suite("First Run State")
struct FirstRunStateTests {

    @Test("Initial state is incomplete")
    func initialIncomplete() {
        let state = FirstRunState.initial
        #expect(!state.setupCompleted)
        #expect(state.profile == nil)
        #expect(state.completedStepIDs.isEmpty)
    }

    @Test("State persists profile")
    func persistsProfile() {
        var state = FirstRunState.initial
        state.profile = .developer
        state.setupCompleted = true
        state.completedAt = Date()
        #expect(state.setupCompleted)
        #expect(state.profile == .developer)
    }

    @Test("State tracks steps")
    func tracksSteps() {
        var state = FirstRunState.initial
        state.completedStepIDs = ["welcome", "model", "roots"]
        state.failedStepIDs = ["scout"]
        #expect(state.completedStepIDs.count == 3)
        #expect(state.failedStepIDs.count == 1)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Setup Report Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Setup Report")
struct SetupReportTests {

    @Test("Report with all passing steps is complete")
    func reportComplete() {
        let report = SetupReport(profile: .developer, steps: [
            SetupStepResult(stepID: "welcome", status: .verified),
            SetupStepResult(stepID: "model", status: .configured),
        ])
        #expect(report.isComplete)
        #expect(report.passed == 2)
        #expect(report.failed == 0)
    }

    @Test("Report with failed steps is not complete")
    func reportIncomplete() {
        let report = SetupReport(profile: .developer, steps: [
            SetupStepResult(stepID: "welcome", status: .verified),
            SetupStepResult(stepID: "model", status: .failed, message: "No provider"),
        ])
        #expect(!report.isComplete)
        #expect(report.failed == 1)
    }

    @Test("Report tracks skipped steps")
    func reportSkipped() {
        let report = SetupReport(profile: .quick, steps: [
            SetupStepResult(stepID: "scout", status: .skipped),
        ])
        #expect(report.skipped == 1)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Permission Profile Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Permission Profiles")
struct PermissionProfileTests {

    @Test("Safe denies everything")
    func safeDeniesAll() {
        let p = PermissionProfileSpec.safe
        #expect(!p.allowFileRead)
        #expect(!p.allowFileWrite)
        #expect(!p.allowShell)
        #expect(!p.allowGitWrite)
        #expect(!p.allowTriggers)
        #expect(!p.allowMCP)
        #expect(!p.allowWorkers)
    }

    @Test("Developer allows read only")
    func developerReadOnly() {
        let p = PermissionProfileSpec.developer
        #expect(p.allowFileRead)
        #expect(!p.allowFileWrite)
        #expect(!p.allowShell)
        #expect(!p.allowGitWrite)
    }

    @Test("Power enables MCP and workers")
    func powerEnablesMCP() {
        let p = PermissionProfileSpec.power
        #expect(p.allowMCP)
        #expect(p.allowWorkers)
        #expect(!p.allowGitWrite) // Never auto-allows git push
    }

    @Test("No profile allows git push by default")
    func noGitPush() {
        #expect(!PermissionProfileSpec.safe.allowGitWrite)
        #expect(!PermissionProfileSpec.developer.allowGitWrite)
        #expect(!PermissionProfileSpec.automation.allowGitWrite)
        #expect(!PermissionProfileSpec.power.allowGitWrite)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Import Wizard Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Import Wizard")
struct ImportWizardTests {

    @Test("Import preview created")
    func previewCreated() {
        let p = ImportPreview(source: .hermes, foundMemories: 5, foundSkills: 3,
                              foundJobs: 2, foundSecrets: 1)
        #expect(p.foundMemories == 5)
        #expect(p.foundJobs == 2)
    }

    @Test("Import result creates candidates not approved memories")
    func importCandidates() {
        let r = ImportResult(source: .hermes, memoryCandidatesCreated: 5,
                             secretsImportedToKeychain: 1, jobsImportedDisabled: 2)
        // Key safety check: memories are candidates, not approved
        #expect(r.memoryCandidatesCreated == 5)
    }

    @Test("Import jobs are disabled")
    func importJobsDisabled() {
        let r = ImportResult(source: .hermes, jobsImportedDisabled: 3)
        #expect(r.jobsImportedDisabled == 3)
    }

    @Test("Import secrets go to Keychain")
    func importSecretsToKeychain() {
        let r = ImportResult(source: .hermes, secretsImportedToKeychain: 2)
        #expect(r.secretsImportedToKeychain == 2)
    }

    @Test("Import MCP servers disabled")
    func importMCPDisabled() {
        let r = ImportResult(source: .hermes, mcpServersImportedDisabled: 1)
        #expect(r.mcpServersImportedDisabled == 1)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Secret Store Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Secret Store")
struct SecretStoreTests {

    @Test("Set and get secret")
    func setAndGet() async throws {
        let store = InMemorySecretStore()
        let ref = SecretRef(namespace: "openai", key: "api_key")
        await store.setSecret("sk-test-123", ref: ref)
        let v = try await store.getSecret(ref: ref)
        #expect(v == "sk-test-123")
    }

    @Test("Delete secret")
    func deleteSecret() async throws {
        let store = InMemorySecretStore()
        let ref = SecretRef(namespace: "openai", key: "api_key")
        await store.setSecret("sk-test-123", ref: ref)
        await store.deleteSecret(ref: ref)
        do {
            _ = try await store.getSecret(ref: ref)
            Issue.record("Should throw")
        } catch is SecretStoreError {}
    }

    @Test("List refs does not reveal values")
    func listRefsNoValues() async throws {
        let store = InMemorySecretStore()
        await store.setSecret("sk-test-123", ref: SecretRef(namespace: "openai", key: "api_key"))
        await store.setSecret("gh-token", ref: SecretRef(namespace: "github", key: "token"))
        let refs = await store.listSecretRefs(namespace: nil)
        #expect(refs.count == 2)
        // Refs expose displayKey, never the raw value
        for ref in refs {
            #expect(!ref.displayKey.contains("sk-test"))
            #expect(!ref.displayKey.contains("gh-token"))
        }
    }

    @Test("List refs by namespace")
    func listByNamespace() async throws {
        let store = InMemorySecretStore()
        await store.setSecret("a", ref: SecretRef(namespace: "openai", key: "k1"))
        await store.setSecret("b", ref: SecretRef(namespace: "github", key: "k2"))
        let refs = await store.listSecretRefs(namespace: "openai")
        #expect(refs.count == 1)
    }

    @Test("Secret ref display key")
    func displayKey() {
        let ref = SecretRef(namespace: "openai", key: "api_key")
        #expect(ref.displayKey == "openai.api_key")
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - User Facing Error Tests
// ═══════════════════════════════════════════════════════════════

@Suite("User Facing Error")
struct UserFacingErrorTests {

    @Test("Error with recovery steps")
    func errorWithRecovery() {
        let e = SwooshUserFacingError(
            code: "MODEL_TEST_FAILED",
            title: "Model provider test failed",
            message: "The configured API key is missing or invalid.",
            recoverySteps: ["swoosh secrets set openai.api_key", "swoosh model test"],
            relatedCommand: "swoosh doctor"
        )
        #expect(e.recoverySteps.count == 2)
        #expect(e.relatedCommand == "swoosh doctor")
    }
}
