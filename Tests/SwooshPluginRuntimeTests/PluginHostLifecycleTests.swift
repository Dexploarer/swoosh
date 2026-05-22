// Tests/SwooshPluginRuntimeTests/PluginHostLifecycleTests.swift — 0.8B

import Testing
import Foundation
@testable import SwooshFirewall
@testable import SwooshPlugins
@testable import SwooshPluginRuntime
@testable import SwooshTools

// MARK: - Fixtures

private func tempRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swoosh-host-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func helloManifest(id: String = "demo", permission: SwooshPermission = .toolRead) -> PluginManifest {
    PluginManifest(
        id: id, name: "Demo \(id)", version: "1.0.0",
        kind: .swift, entrypoint: .swiftModule(id),
        requestedPermissions: [permission.rawValue],
        tools: [PluginToolManifest(
            name: "echo", description: "Echo input",
            permission: permission, risk: .readOnly, requiresApproval: false
        )]
    )
}

// One generic entrypoint that carries its identity via an instance
// property; the test registers it with an explicit ID via
// `SwiftPluginRegistry.register(id:_:)`. No mutable static state, so
// parallel test execution stays safe.
private struct EchoEntrypoint: SwiftPluginEntrypoint {
    let identity: String
    static var pluginID: String { "unused-default" }
    init(identity: String) { self.identity = identity }
    func call(toolName: String, args: JSONValue, context: ToolContext) async throws -> JSONValue {
        .object(["pluginID": .string(identity), "toolName": .string(toolName), "echoed": args])
    }
}

private actor SimpleAudit: AuditLogging {
    var entries: [AuditEntry] = []
    func append(_ event: AuditEntry) async throws { entries.append(event) }
    func tail(limit: Int) async -> [AuditEntry] { Array(entries.suffix(limit)) }
    func search(query: String, limit: Int) async -> [AuditEntry] {
        entries.filter { $0.detail.contains(query) }.suffix(limit).map { $0 }
    }
    func getEvent(id: String) async -> AuditEntry? { entries.first { $0.id == id } }
}

private actor AutoApprove: ApprovalRequesting {
    func requireApproval(_ request: ToolApprovalRequest) async throws {}
    func listPending() async -> [ToolApprovalRequest] { [] }
    func resolve(id: String, decision: ApprovalDecision, reason: String?) async throws {}
}

private func makeStack(
    baseline: Set<SwooshPermission> = []
) async -> (PluginHost, ToolRegistry, SwooshFirewallActor, PluginRegistry, FilePluginStore, SwiftPluginRegistry, URL) {
    let root = tempRoot()
    let store = FilePluginStore(root: root)
    let audit = SimpleAudit()
    let firewall = SwooshFirewallActor(granted: baseline)
    let toolRegistry = ToolRegistry(
        firewall: firewall, audit: audit, approvals: AutoApprove()
    )
    let registry = PluginRegistry(audit: audit)
    let swift = SwiftPluginRegistry()
    let host = PluginHost(
        store: store, registry: registry, toolRegistry: toolRegistry,
        firewall: firewall,
        executors: [SwiftPluginExecutor(registry: swift)],
        baselineGrants: baseline,
        pluginsRoot: root
    )
    return (host, toolRegistry, firewall, registry, store, swift, root)
}

// MARK: - Tests

@Suite("PluginHost lifecycle")
struct PluginHostLifecycleTests {

    @Test("install rejects invalid manifest")
    func installRejectsInvalid() async throws {
        let (host, _, _, _, _, _, root) = await makeStack()
        defer { try? FileManager.default.removeItem(at: root) }
        var bad = helloManifest()
        bad.requestedPermissions.append("not_a_real_perm")
        do {
            try await host.install(bad)
            Issue.record("install should have thrown")
        } catch PluginError.validationFailed(_, let errs) {
            #expect(errs.contains(where: {
                if case .unknownPermission = $0 { return true }; return false
            }))
        }
    }

    @Test("enable grants permissions and registers tool")
    func enableGrantsAndRegisters() async throws {
        let (host, toolRegistry, firewall, _, _, swift, root) = await makeStack(baseline: [])
        defer { try? FileManager.default.removeItem(at: root) }
        await swift.register(id: "demo", EchoEntrypoint(identity: "demo"))
        try await host.install(helloManifest(permission: .networkAccess))
        try await host.enable("demo")

        #expect(await firewall.isGranted(.networkAccess))
        let descriptors = await toolRegistry.listAvailable(
            context: ToolContext(sessionID: "t")
        )
        #expect(descriptors.contains(where: { $0.name == "plugin.echo" }))
    }

    @Test("disable revokes exclusive permissions and unregisters tool")
    func disableRevokes() async throws {
        let (host, toolRegistry, firewall, _, _, swift, root) = await makeStack(baseline: [])
        defer { try? FileManager.default.removeItem(at: root) }
        await swift.register(id: "demo", EchoEntrypoint(identity: "demo"))
        try await host.install(helloManifest(permission: .networkAccess))
        try await host.enable("demo")
        try await host.disable("demo")

        #expect(await !firewall.isGranted(.networkAccess))
        let descriptors = await toolRegistry.listAvailable(
            context: ToolContext(sessionID: "t")
        )
        #expect(!descriptors.contains(where: { $0.name == "plugin.echo" }))
    }

    @Test("disable does NOT revoke baseline grant")
    func disablePreservesBaseline() async throws {
        let (host, _, firewall, _, _, swift, root) = await makeStack(
            baseline: [.networkAccess]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        await swift.register(id: "demo", EchoEntrypoint(identity: "demo"))
        try await host.install(helloManifest(permission: .networkAccess))
        try await host.enable("demo")
        try await host.disable("demo")
        #expect(await firewall.isGranted(.networkAccess))
    }

    @Test("disable preserves grant another plugin still needs")
    func disablePreservesSharedGrant() async throws {
        let (host, _, firewall, _, _, swift, root) = await makeStack(baseline: [])
        defer { try? FileManager.default.removeItem(at: root) }
        // Two plugins share `.networkAccess`. After disabling one, the
        // other's grant must remain in force.
        await swift.register(id: "a", EchoEntrypoint(identity: "a"))
        try await host.install(helloManifest(id: "a", permission: .networkAccess))
        try await host.enable("a")
        await swift.register(id: "b", EchoEntrypoint(identity: "b"))
        try await host.install(helloManifest(id: "b", permission: .networkAccess))
        try await host.enable("b")

        try await host.disable("a")
        #expect(await firewall.isGranted(.networkAccess))

        try await host.disable("b")
        #expect(await !firewall.isGranted(.networkAccess))
    }

    @Test("bootstrap re-enables previously enabled plugins")
    func bootstrapRehydrates() async throws {
        let (host, _, firewall, _, store, swift, root) = await makeStack(baseline: [])
        defer { try? FileManager.default.removeItem(at: root) }
        await swift.register(id: "demo", EchoEntrypoint(identity: "demo"))
        try await host.install(helloManifest(permission: .networkAccess))
        try await host.enable("demo")

        // Build a fresh host on the same store, simulating daemon restart.
        let audit = SimpleAudit()
        let firewall2 = SwooshFirewallActor(granted: [])
        let toolRegistry2 = ToolRegistry(firewall: firewall2, audit: audit, approvals: AutoApprove())
        let registry2 = PluginRegistry(audit: audit)
        let swift2 = SwiftPluginRegistry()
        await swift2.register(id: "demo", EchoEntrypoint(identity: "demo"))
        let host2 = PluginHost(
            store: store, registry: registry2, toolRegistry: toolRegistry2,
            firewall: firewall2,
            executors: [SwiftPluginExecutor(registry: swift2)],
            baselineGrants: [],
            pluginsRoot: root
        )
        try await host2.bootstrap()
        #expect(await firewall2.isGranted(.networkAccess))
        let descriptors = await toolRegistry2.listAvailable(
            context: ToolContext(sessionID: "t")
        )
        #expect(descriptors.contains(where: { $0.name == "plugin.echo" }))
        _ = firewall
    }
}

@Suite("Plugin end-to-end through ToolRegistry")
struct PluginEndToEndTests {

    @Test("calling an enabled plugin tool returns the plugin's output")
    func endToEnd() async throws {
        let (host, toolRegistry, _, _, _, swift, root) = await makeStack(baseline: [])
        defer { try? FileManager.default.removeItem(at: root) }
        await swift.register(id: "demo", EchoEntrypoint(identity: "demo"))
        try await host.install(helloManifest(permission: .toolRead))
        try await host.enable("demo")

        let output = try await toolRegistry.call(
            name: ToolName("plugin.echo"),
            input: .object(["message": .string("hi")]),
            context: ToolContext(sessionID: "t")
        )
        guard case .object(let dict) = output else {
            Issue.record("expected object, got \(output)")
            return
        }
        #expect(dict["pluginID"] == .string("demo"))
    }

    @Test("calling a tool after disable fails")
    func callAfterDisable() async throws {
        let (host, toolRegistry, _, _, _, swift, root) = await makeStack(baseline: [])
        defer { try? FileManager.default.removeItem(at: root) }
        await swift.register(id: "demo", EchoEntrypoint(identity: "demo"))
        try await host.install(helloManifest(permission: .toolRead))
        try await host.enable("demo")
        try await host.disable("demo")

        do {
            _ = try await toolRegistry.call(
                name: ToolName("plugin.echo"),
                input: .object([:]),
                context: ToolContext(sessionID: "t")
            )
            Issue.record("should have thrown ToolError.notFound")
        } catch ToolError.notFound {
            // expected — the bridge was unregistered
        }
    }
}
