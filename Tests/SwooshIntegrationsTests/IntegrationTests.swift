// Tests/SwooshIntegrationsTests/IntegrationTests.swift — 0.8B

import Testing
import Foundation
@testable import SwooshIntegrations
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Integration Profile Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Integration Profile")
struct IntegrationProfileTests {

    @Test("Profile created")
    func profileCreated() {
        let p = IntegrationProfile(name: "Linear", kind: .remoteMCP, serverID: "linear")
        #expect(p.name == "Linear")
        #expect(p.kind == .remoteMCP)
        #expect(!p.enabled)
    }

    @Test("Default auth not configured")
    func defaultAuthNotConfigured() {
        let p = IntegrationProfile(name: "Test", kind: .remoteMCP)
        #expect(p.authStatus == .notConfigured)
    }

    @Test("Default health unknown")
    func defaultHealthUnknown() {
        let p = IntegrationProfile(name: "Test", kind: .remoteMCP)
        #expect(p.health == .unknown)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Integration Registry Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Integration Registry")
struct IntegrationRegistryTests {

    @Test("Add and list profiles")
    func addAndList() async throws {
        let reg = IntegrationRegistry()
        await reg.addProfile(IntegrationProfile(name: "Linear", kind: .remoteMCP))
        let list = await reg.listProfiles()
        #expect(list.count == 1)
    }

    @Test("Save and get snapshot")
    func snapshot() async throws {
        let reg = IntegrationRegistry()
        let snap = IntegrationCapabilitySnapshot(
            serverID: "linear", toolNames: ["read_issues", "create_issue"]
        )
        await reg.saveSnapshot(snap)
        let got = await reg.getSnapshot(snap.id)
        #expect(got?.toolNames.count == 2)
    }

    @Test("Latest snapshot")
    func latestSnapshot() async throws {
        let reg = IntegrationRegistry()
        await reg.saveSnapshot(IntegrationCapabilitySnapshot(
            serverID: "linear", toolNames: ["a"], capturedAt: Date().addingTimeInterval(-100)
        ))
        await reg.saveSnapshot(IntegrationCapabilitySnapshot(
            serverID: "linear", toolNames: ["a", "b"]
        ))
        let latest = await reg.latestSnapshot(serverID: "linear")
        #expect(latest?.toolNames.count == 2)
    }

    @Test("Record health")
    func recordHealth() async throws {
        let reg = IntegrationRegistry()
        let h = IntegrationHealth(integrationID: "i1", status: .healthy)
        await reg.recordHealth(h)
        let got = await reg.getHealth("i1")
        #expect(got?.status == .healthy)
    }

    @Test("Degraded health writes audit")
    func degradedHealthAudit() async throws {
        let reg = IntegrationRegistry()
        await reg.recordHealth(IntegrationHealth(integrationID: "i1", status: .degraded, errorSummary: "Timeout"))
        let log = await reg.getAuditLog()
        #expect(log.contains { $0.kind == .healthDegraded })
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Capability Diff Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Capability Diff")
struct CapabilityDiffTests {

    @Test("Added tool detected")
    func addedTool() {
        let differ = CapabilityDiffer()
        let old = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: ["read"])
        let new = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: ["read", "write"])
        let diff = differ.diff(old: old, new: new)
        #expect(diff.addedTools == ["write"])
        #expect(diff.removedTools.isEmpty)
        #expect(diff.requiresUserReview)
    }

    @Test("Removed tool detected")
    func removedTool() {
        let differ = CapabilityDiffer()
        let old = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: ["read", "write"])
        let new = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: ["read"])
        let diff = differ.diff(old: old, new: new)
        #expect(diff.removedTools == ["write"])
        #expect(diff.requiresUserReview)
    }

    @Test("No changes = no review needed")
    func noChanges() {
        let differ = CapabilityDiffer()
        let old = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: ["read"])
        let new = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: ["read"])
        let diff = differ.diff(old: old, new: new)
        #expect(!diff.hasChanges)
        #expect(!diff.requiresUserReview)
    }

    @Test("First snapshot has all added")
    func firstSnapshot() {
        let differ = CapabilityDiffer()
        let new = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: ["read", "write"])
        let diff = differ.diff(old: nil, new: new)
        #expect(diff.addedTools.count == 2)
        #expect(diff.requiresUserReview)
    }

    @Test("Resource changes detected")
    func resourceChanges() {
        let differ = CapabilityDiffer()
        let old = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: [], resourceURIs: ["file:///a"])
        let new = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: [], resourceURIs: ["file:///a", "file:///b"])
        let diff = differ.diff(old: old, new: new)
        #expect(diff.addedResources == ["file:///b"])
    }

    @Test("Prompt changes detected")
    func promptChanges() {
        let differ = CapabilityDiffer()
        let old = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: [], promptNames: ["summarize"])
        let new = IntegrationCapabilitySnapshot(serverID: "s1", toolNames: [], promptNames: [])
        let diff = differ.diff(old: old, new: new)
        #expect(diff.removedPrompts == ["summarize"])
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Integration Health Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Integration Health")
struct IntegrationHealthTests {

    @Test("Health healthy")
    func healthy() {
        let h = IntegrationHealth(integrationID: "i1", status: .healthy, latencyMs: 45)
        #expect(h.status == .healthy)
        #expect(h.latencyMs == 45)
    }

    @Test("Health auth expired")
    func authExpired() {
        let h = IntegrationHealth(integrationID: "i1", status: .degraded, authStatus: .tokenExpired)
        #expect(h.authStatus == .tokenExpired)
    }

    @Test("Health with capability drift")
    func capabilityDrift() {
        let h = IntegrationHealth(integrationID: "i1", status: .degraded, capabilityDiffID: "diff_123")
        #expect(h.capabilityDiffID != nil)
    }

    @Test("Health network failure")
    func networkFailure() {
        let h = IntegrationHealth(integrationID: "i1", status: .unhealthy, errorSummary: "Connection refused")
        #expect(h.errorSummary != nil)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Integration Audit Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Integration Audit")
struct IntegrationAuditTests {

    @Test("Profile creation audited")
    func profileCreationAudited() async throws {
        let reg = IntegrationRegistry()
        await reg.addProfile(IntegrationProfile(name: "Test", kind: .remoteMCP))
        let log = await reg.getAuditLog()
        #expect(log.contains { $0.kind == .profileCreated })
    }

    @Test("Snapshot creation audited")
    func snapshotCreationAudited() async throws {
        let reg = IntegrationRegistry()
        await reg.saveSnapshot(IntegrationCapabilitySnapshot(serverID: "s1", toolNames: ["a"]))
        let log = await reg.getAuditLog()
        #expect(log.contains { $0.kind == .snapshotCreated })
    }
}
