// Tests/SwooshPluginsTests/PluginValidationTests.swift — 0.8B Validation Tests
//
// Covers the typed-permission validation added in 0.8B. Old tests in
// PluginTests.swift continue to cover the rest of the surface.

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshTools

private func validManifest(
    id: String = "test-plugin",
    requestedPermissions: [String] = ["toolRead"],
    tools: [PluginToolManifest] = [
        PluginToolManifest(
            name: "echo", description: "Echo input",
            permission: .toolRead, risk: .readOnly, requiresApproval: false
        )
    ],
    kind: PluginKind = .swift,
    entrypoint: PluginEntrypoint = .swiftModule("test-plugin")
) -> PluginManifest {
    PluginManifest(
        id: id, name: "Test", version: "1.0.0",
        kind: kind, entrypoint: entrypoint,
        requestedPermissions: requestedPermissions, tools: tools
    )
}

@Suite("Plugin Validation")
struct PluginValidationTests {

    @Test("Valid manifest passes")
    func valid() {
        #expect(validManifest().validate().isEmpty)
    }

    @Test("Unknown permission rejected")
    func unknownPermission() {
        let m = validManifest(requestedPermissions: ["toolRead", "definitely_not_a_real_permission"])
        let errs = m.validate()
        #expect(errs.contains(where: { if case .unknownPermission = $0 { return true }; return false }))
    }

    @Test("Reserved admin permission rejected")
    func reservedAdminPermission() {
        let m = validManifest(requestedPermissions: ["toolRead", "pluginEnable"])
        let errs = m.validate()
        #expect(errs.contains(where: { if case .reservedAdminPermission = $0 { return true }; return false }))
    }

    @Test("Tool permission not in requestedPermissions rejected")
    func toolPermissionNotRequested() {
        let m = validManifest(
            requestedPermissions: ["toolRead"],
            tools: [
                PluginToolManifest(
                    name: "tool", description: "x",
                    permission: .networkAccess,  // not requested
                    risk: .medium, requiresApproval: true
                )
            ]
        )
        let errs = m.validate()
        #expect(errs.contains(where: {
            if case .toolPermissionNotRequested = $0 { return true }; return false
        }))
    }

    @Test("Duplicate tool name rejected")
    func duplicateToolName() {
        let m = validManifest(tools: [
            PluginToolManifest(name: "echo", description: "", permission: .toolRead),
            PluginToolManifest(name: "echo", description: "", permission: .toolRead),
        ])
        let errs = m.validate()
        #expect(errs.contains(where: {
            if case .duplicateToolName = $0 { return true }; return false
        }))
    }

    @Test("Entrypoint kind mismatch rejected")
    func entrypointMismatch() {
        let m = validManifest(
            kind: .swift,
            entrypoint: .executable(path: "/bin/true", arguments: [])
        )
        let errs = m.validate()
        #expect(errs.contains(where: {
            if case .entrypointKindMismatch = $0 { return true }; return false
        }))
    }

    @Test("Empty ID rejected")
    func emptyID() {
        let m = validManifest(id: "")
        let errs = m.validate()
        #expect(errs.contains(.emptyID))
    }

    @Test("Path-traversal IDs rejected")
    func pathTraversalRejected() {
        // The store and host both treat `id` as a filesystem path
        // component; any of these would escape the plugins root.
        let attacks = [
            "../escape",
            "../../.ssh",
            "a/b",
            "a.b",            // could collide with manifest.json siblings
            "a b",            // shell-quoting hazard
            ".",
            "..",
            "/absolute",
        ]
        for id in attacks {
            let m = validManifest(id: id)
            let errs = m.validate()
            #expect(
                errs.contains(where: {
                    if case .invalidID = $0 { return true }; return false
                }),
                "expected invalidID error for id `\(id)`, got \(errs)"
            )
        }
    }

    @Test("Safe IDs accepted")
    func safeIDsAccepted() {
        let safe = ["hello-swift", "hello_exec", "PluginA42", "x"]
        for id in safe {
            let m = validManifest(id: id)
            let errs = m.validate()
            #expect(errs.isEmpty, "id `\(id)` should validate; got \(errs)")
        }
    }
}

@Suite("Plugin Audit Forwarding")
struct PluginAuditForwardingTests {

    actor RecordingAudit: AuditLogging {
        var entries: [AuditEntry] = []
        func append(_ event: AuditEntry) async throws { entries.append(event) }
        func tail(limit: Int) async -> [AuditEntry] { Array(entries.suffix(limit)) }
        func search(query: String, limit: Int) async -> [AuditEntry] {
            entries.filter { $0.detail.contains(query) }.suffix(limit).map { $0 }
        }
        func getEvent(id: String) async -> AuditEntry? {
            entries.first { $0.id == id }
        }
        func allEntries() async -> [AuditEntry] { entries }
    }

    @Test("Audit forwarded on register")
    func forwardedOnRegister() async throws {
        let recorder = RecordingAudit()
        let registry = PluginRegistry(audit: recorder)
        try await registry.register(validManifest())
        let entries = await recorder.allEntries()
        #expect(entries.contains(where: {
            $0.kind == .pluginEvent && $0.detail.contains("discovered")
        }))
    }

    @Test("Audit forwarded on enable")
    func forwardedOnEnable() async throws {
        let recorder = RecordingAudit()
        let registry = PluginRegistry(audit: recorder)
        try await registry.register(validManifest())
        try await registry.enable("test-plugin")
        let entries = await recorder.allEntries()
        let enabledEvents = entries.filter {
            $0.kind == .pluginEvent && $0.detail.contains("enabled")
        }
        #expect(!enabledEvents.isEmpty)
    }

    @Test("Sandbox violation marked unsuccessful")
    func sandboxViolationUnsuccessful() async throws {
        let recorder = RecordingAudit()
        let registry = PluginRegistry(audit: recorder)
        try await registry.register(validManifest())
        _ = try await registry.validateSandbox(pluginID: "test-plugin", action: .filesystemRead)
        let entries = await recorder.allEntries()
        let violation = entries.first { $0.detail.contains("sandboxViolation") }
        #expect(violation != nil)
        #expect(violation?.success == false)
    }

    @Test("No audit forwarding when audit is nil")
    func nilAuditOK() async throws {
        let registry = PluginRegistry()
        try await registry.register(validManifest())
        let internalLog = await registry.getAuditLog()
        #expect(!internalLog.isEmpty)
    }
}
