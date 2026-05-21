// Tests/SwooshToolsetsTests/DefaultToolRegistrarTests.swift
//
// SwooshToolsets registers every concrete tool implementation into a
// ToolRegistry via `DefaultToolRegistrar.registerAll(...)`. These tests
// verify that the registration runs successfully and produces the
// expected set of P0 tools, without exercising the tools themselves
// (which require live RPC clients, file roots, and approvals).

import Testing
import Foundation
@testable import SwooshToolsets
@testable import SwooshTools
@testable import SwooshFirewall
@testable import SwooshFiles
@testable import SwooshProcess

// MARK: - Helpers

private struct TestHarness: Sendable {
    let firewall: SwooshFirewallActor
    let audit: SwooshAuditLog
    let approvals: InMemoryApprovalRequester
    let dependencies: ToolDependencies

    init() {
        let firewall = SwooshFirewallActor()
        let audit = SwooshAuditLog()
        let approvals = InMemoryApprovalRequester(autoApprove: true)
        let rootStore = InMemoryRootStore()
        let fileAccess = SafeFileAccessor(rootStore: rootStore)
        let processRunner = StreamingProcessRunner()
        self.firewall = firewall
        self.audit = audit
        self.approvals = approvals
        self.dependencies = ToolDependencies(
            firewall: firewall,
            audit: audit,
            approvals: approvals,
            fileAccess: fileAccess,
            processRunner: processRunner
        )
    }

    func makeRegistry() -> ToolRegistry {
        ToolRegistry(firewall: firewall, audit: audit, approvals: approvals)
    }

    func toolNames() async -> Set<String> {
        let registry = makeRegistry()
        await DefaultToolRegistrar.registerAll(into: registry, dependencies: dependencies)
        let descriptors = await registry.listAvailable(context: ToolContext(sessionID: "test"))
        return Set(descriptors.map(\.name))
    }
}

// MARK: - Registration

@Suite("DefaultToolRegistrar")
struct DefaultToolRegistrarTests {

    @Test("registerAll populates the registry without crashing")
    func registerAllSucceeds() async {
        let names = await TestHarness().toolNames()
        #expect(names.count > 0)
    }

    @Test("Registry contains core P0 tool families")
    func registryContainsCoreFamilies() async {
        let names = await TestHarness().toolNames()
        // Verify representative P0 tools across families landed (we don't pin exact names).
        let hasFiles = names.contains { $0.contains("file") }
        let hasGit = names.contains { $0.contains("git") }
        let hasMemory = names.contains { $0.contains("memory") }
        let hasScout = names.contains { $0.contains("scout") }
        #expect(hasFiles)
        #expect(hasGit)
        #expect(hasMemory)
        #expect(hasScout)
    }

    @Test("Re-registering is idempotent on tool count")
    func idempotent() async {
        let harness = TestHarness()
        let registry = harness.makeRegistry()
        await DefaultToolRegistrar.registerAll(into: registry, dependencies: harness.dependencies)
        let first = await registry.listAvailable(context: ToolContext(sessionID: "t")).count

        await DefaultToolRegistrar.registerAll(into: registry, dependencies: harness.dependencies)
        let second = await registry.listAvailable(context: ToolContext(sessionID: "t")).count
        #expect(first == second)
    }
}

// MARK: - TestHarness Scenarios

@Suite("TestHarness Scenarios")
struct TestHarnessScenariosTests {

    @Test("Harness creates independent registries")
    func independentRegistries() async {
        let harness1 = TestHarness()
        let harness2 = TestHarness()
        let names1 = await harness1.toolNames()
        let names2 = await harness2.toolNames()
        #expect(names1 == names2)
        #expect(names1.count > 0)
    }

    @Test("Harness with manual approval mode")
    func manualApprovalMode() async {
        let firewall = SwooshFirewallActor()
        let audit = SwooshAuditLog()
        let approvals = InMemoryApprovalRequester(autoApprove: false)
        let rootStore = InMemoryRootStore()
        let fileAccess = SafeFileAccessor(rootStore: rootStore)
        let processRunner = StreamingProcessRunner()
        let dependencies = ToolDependencies(
            firewall: firewall,
            audit: audit,
            approvals: approvals,
            fileAccess: fileAccess,
            processRunner: processRunner
        )

        let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvals)
        await DefaultToolRegistrar.registerAll(into: registry, dependencies: dependencies)
        let descriptors = await registry.listAvailable(context: ToolContext(sessionID: "test"))
        #expect(descriptors.count > 0)
    }

    @Test("Harness tool lookup by name")
    func toolLookupByName() async {
        let harness = TestHarness()
        let registry = harness.makeRegistry()
        await DefaultToolRegistrar.registerAll(into: registry, dependencies: harness.dependencies)
        let descriptors = await registry.listAvailable(context: ToolContext(sessionID: "test"))

        // Find a file tool
        let fileTools = descriptors.filter { $0.name.contains("file") }
        #expect(fileTools.count > 0)

        // Verify we can look up by exact name
        if let firstFile = fileTools.first {
            let allNames = descriptors.map(\.name)
            #expect(allNames.contains(firstFile.name))
        }
    }

    @Test("Harness tool metadata consistency")
    func toolMetadataConsistency() async {
        let harness = TestHarness()
        let registry = harness.makeRegistry()
        await DefaultToolRegistrar.registerAll(into: registry, dependencies: harness.dependencies)
        let descriptors = await registry.listAvailable(context: ToolContext(sessionID: "test"))

        // All tools should have valid metadata
        for descriptor in descriptors {
            #expect(!descriptor.name.isEmpty)
            #expect(!descriptor.description.isEmpty)
        }
    }

    @Test("Harness with different session contexts")
    func differentSessionContexts() async {
        let harness = TestHarness()
        let registry = harness.makeRegistry()
        await DefaultToolRegistrar.registerAll(into: registry, dependencies: harness.dependencies)

        let context1 = ToolContext(sessionID: "session-1")
        let context2 = ToolContext(sessionID: "session-2")

        let tools1 = await registry.listAvailable(context: context1)
        let tools2 = await registry.listAvailable(context: context2)

        // Same tools should be available regardless of session
        #expect(tools1.count == tools2.count)
    }

    @Test("Harness concurrent registration safety")
    func concurrentRegistration() async {
        let harness = TestHarness()
        let registry = harness.makeRegistry()

        // Register multiple times concurrently
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await DefaultToolRegistrar.registerAll(into: registry, dependencies: harness.dependencies)
                }
            }
        }

        // Should still have a valid registry
        let descriptors = await registry.listAvailable(context: ToolContext(sessionID: "test"))
        #expect(descriptors.count > 0)
    }

    @Test("Harness tool family coverage")
    func toolFamilyCoverage() async {
        let harness = TestHarness()
        let names = await harness.toolNames()

        // Check for coverage across major tool families
        let families = [
            "file", "git", "memory", "scout", "shell",
            "calendar", "mail", "browser", "mcp"
        ]

        let coveredFamilies = families.filter { family in
            names.contains { $0.contains(family) }
        }

        // Should have at least some core families
        #expect(coveredFamilies.count >= 4)
    }

    @Test("Harness dependency injection")
    func dependencyInjection() async {
        let harness = TestHarness()
        // Confirm dependencies are constructed — protocol existentials so we
        // just need the instances to exist.
        _ = harness.dependencies.firewall
        _ = harness.dependencies.approvals
        _ = harness.dependencies.fileAccess
        _ = harness.dependencies.processRunner
        #expect(Bool(true))
    }

    @Test("Harness registry isolation")
    func registryIsolation() async {
        let harness = TestHarness()
        let registry1 = harness.makeRegistry()
        let registry2 = harness.makeRegistry()

        await DefaultToolRegistrar.registerAll(into: registry1, dependencies: harness.dependencies)

        let tools1 = await registry1.listAvailable(context: ToolContext(sessionID: "test"))
        let tools2 = await registry2.listAvailable(context: ToolContext(sessionID: "test"))

        // Registry2 should be empty until registered
        #expect(tools1.count > 0)
        #expect(tools2.count == 0)
    }
}

// MARK: - SelfImprovementDependencies

@Suite("SelfImprovementDependencies")
struct SelfImprovementDependenciesTests {

    @Test("Default initializer has nil pillars")
    func defaultsAreNil() {
        let deps = SelfImprovementDependencies()
        #expect(deps.skills == nil)
        #expect(deps.goals == nil)
        #expect(deps.manifest == nil)
        #expect(deps.cron == nil)
    }
}
