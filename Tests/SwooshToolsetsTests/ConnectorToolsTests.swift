// Tests/SwooshToolsetsTests/ConnectorToolsTests.swift
import Foundation
import Testing
@testable import SwooshToolsets
import SwooshChatSDK
import SwooshFirewall
import SwooshFiles
import SwooshProcess
import SwooshTools

@Suite("Connector tools")
struct ConnectorToolsTests {
    @Test("connector.status executes through ToolRegistry with saved toggles and Keychain refs")
    func connectorStatusExecutesThroughRegistry() async throws {
        let firewall = SwooshFirewallActor(granted: [.toolRead])
        let audit = SwooshAuditLog()
        let approvals = InMemoryApprovalRequester(autoApprove: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let adapterStore = ChatAdapterToggleStore(url: root.appending(path: "chat-adapters.json"))
        try await adapterStore.set(.discord, enabled: true)
        let dependencies = ToolDependencies(
            firewall: firewall,
            audit: audit,
            approvals: approvals,
            fileAccess: SafeFileAccessor(rootStore: InMemoryRootStore()),
            processRunner: StreamingProcessRunner(),
            secrets: TestSecretResolver(values: ["discord.bot_token": "token"])
        )
        let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvals)
        await registry.register(TypeErasedTool(ConnectorStatusTool(
            dependencies: dependencies,
            adapterStore: adapterStore,
            liveHealthChecker: StaticConnectorHealthChecker(health: .verified(account: "detour", detail: "verified"))
        )))

        let output = try await registry.call(
            name: "connector.status",
            input: .object(["connectorID": .string("discord")]),
            context: ToolContext(sessionID: "connector-test", isModelInvocation: false)
        )
        guard case .object(let object) = output,
              case .array(let connectors) = object["connectors"],
              case .object(let discord)? = connectors.first,
              case .bool(true) = discord["enabled"],
              case .bool(true) = discord["usable"] else {
            Issue.record("connector.status did not return a usable Discord connector")
            return
        }
    }

    @Test("connector.status does not mark disabled requested connector as usable")
    func connectorStatusRequiresUsableRequestedConnector() async throws {
        let firewall = SwooshFirewallActor(granted: [.toolRead])
        let audit = SwooshAuditLog()
        let approvals = InMemoryApprovalRequester(autoApprove: true)
        let dependencies = ToolDependencies(
            firewall: firewall,
            audit: audit,
            approvals: approvals,
            fileAccess: SafeFileAccessor(rootStore: InMemoryRootStore()),
            processRunner: StreamingProcessRunner(),
            secrets: TestSecretResolver(values: [:])
        )
        let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvals)
        await registry.register(TypeErasedTool(ConnectorStatusTool(dependencies: dependencies)))

        let output = try await registry.call(
            name: "connector.status",
            input: .object(["connectorID": .string("discord")]),
            context: ToolContext(sessionID: "connector-disabled-test", isModelInvocation: false)
        )
        guard case .object(let object) = output,
              case .bool(false) = object["success"],
              case .array(let doctor) = object["doctor"],
              !doctor.isEmpty else {
            Issue.record("connector.status marked a disabled Discord connector as successful")
            return
        }
    }
}

private struct TestSecretResolver: SecretResolving {
    let values: [String: String]

    func resolve(ref: String) async throws -> String {
        guard let value = values[ref] else {
            throw ToolError.executionFailed("missing test secret")
        }
        return value
    }
}

private struct StaticConnectorHealthChecker: ConnectorLiveHealthChecking {
    let health: ConnectorLiveHealth

    func check(
        definition: ChatAdapterDefinition,
        sources: [String],
        dependencies: ToolDependencies
    ) async -> ConnectorLiveHealth {
        health
    }
}
