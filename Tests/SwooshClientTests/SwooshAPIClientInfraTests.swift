// Tests/SwooshClientTests/SwooshAPIClientInfraTests.swift — 0.4A
//
// Coverage for the infra-tier API methods — MCP, firewall, cron, wallet
// ops, plus the plugins family. The audit flagged these as untested
// despite being the bulk of the tier-1 push.

import Foundation
import Testing
@testable import SwooshClient

@Suite("SwooshAPIClient — Infra endpoints")
struct SwooshAPIClientInfraTests {

    private func baseURL() -> URL { URL(string: "http://127.0.0.1:8787/")! }
    private func makeClient() -> SwooshAPIClient {
        SwooshAPIClient(baseURL: baseURL(), token: "pair-token", session: MockURLProtocol.makeSession())
    }

    // MARK: - MCP CRUD

    @Test("addMCPServer / removeMCPServer / connect / disconnect / tools route correctly")
    func mcpMutations() async throws {
        let summary = MCPServerRuntimeSummary(
            id: "pay", name: "Pay", description: nil, enabled: true,
            trustLevel: "userApproved", state: "connected", transport: "stdio",
            toolCount: 0, importedToolCount: 0, tools: []
        )
        let mutation = try JSONEncoder.swooshDefault.encode(MCPServerMutationResponse(server: summary, message: "ok"))
        let list = try JSONEncoder.swooshDefault.encode(MCPServersResponse(servers: []))
        let tools = try JSONEncoder.swooshDefault.encode(MCPServerToolsResponse(serverID: "pay", tools: []))

        try await MockURLProtocol.with({ request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/mcp/servers"):
                let payload = try! JSONDecoder.swooshDefault.decode(MCPServerCreateRequest.self, from: request.bodyData())
                #expect(payload.id == "pay")
                #expect(payload.transport == "stdio")
                return (200, ["Content-Type": "application/json"], mutation)
            case ("DELETE", "/api/mcp/servers/pay"):
                return (200, ["Content-Type": "application/json"], list)
            case ("POST", "/api/mcp/servers/pay/connect"):
                return (200, ["Content-Type": "application/json"], mutation)
            case ("POST", "/api/mcp/servers/pay/disconnect"):
                return (200, ["Content-Type": "application/json"], mutation)
            case ("GET", "/api/mcp/servers/pay/tools"):
                return (200, ["Content-Type": "application/json"], tools)
            default:
                Issue.record("unexpected request: \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
                return (500, [:], Data())
            }
        }) {
            let client = makeClient()
            _ = try await client.addMCPServer(.init(
                id: "pay", name: "Pay", transport: "stdio",
                command: "/usr/local/bin/pay-mcp"
            ))
            _ = try await client.removeMCPServer(id: "pay")
            _ = try await client.connectMCPServer(id: "pay")
            _ = try await client.disconnectMCPServer(id: "pay")
            _ = try await client.mcpServerTools(id: "pay")
        }
    }

    // MARK: - Firewall

    @Test("firewallGrants / updateFirewall / revokeFirewall / checkFirewall route correctly")
    func firewallMutations() async throws {
        let response = FirewallResponse(granted: ["solanaRead"], denied: [])
        let mutation = FirewallMutationResponse(firewall: response, message: "ok")
        let check = FirewallCheckResponse(permission: "solanaRead", granted: true, denied: false)

        let listBody = try JSONEncoder.swooshDefault.encode(response)
        let mutBody = try JSONEncoder.swooshDefault.encode(mutation)
        let checkBody = try JSONEncoder.swooshDefault.encode(check)

        try await MockURLProtocol.with({ request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/firewall/grants"):
                return (200, ["Content-Type": "application/json"], listBody)
            case ("POST", "/api/firewall/grants"):
                let payload = try! JSONDecoder.swooshDefault.decode(FirewallGrantRequest.self, from: request.bodyData())
                #expect(payload.permission == "solanaRead")
                return (200, ["Content-Type": "application/json"], mutBody)
            case ("DELETE", "/api/firewall/grants/solanaRead"):
                return (200, ["Content-Type": "application/json"], listBody)
            case ("POST", "/api/firewall/check"):
                let payload = try! JSONDecoder.swooshDefault.decode(FirewallCheckRequest.self, from: request.bodyData())
                #expect(payload.permission == "solanaRead")
                return (200, ["Content-Type": "application/json"], checkBody)
            default:
                Issue.record("unexpected request: \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
                return (500, [:], Data())
            }
        }) {
            let client = makeClient()
            _ = try await client.firewallGrants()
            _ = try await client.updateFirewall(.init(permission: "solanaRead", decision: "grant"))
            _ = try await client.revokeFirewall(permission: "solanaRead")
            _ = try await client.checkFirewall(.init(permission: "solanaRead"))
        }
    }

    // MARK: - Cron

    @Test("Cron CRUD endpoints route correctly")
    func cronMutations() async throws {
        let job = CronJobRecordSummary(
            id: "c-1", name: "standup", state: "scheduled", enabled: true,
            nextRunAt: Date(timeIntervalSince1970: 1_800_000_000), lastRunAt: nil
        )
        let list = try JSONEncoder.swooshDefault.encode(CronJobsResponse(jobs: [job]))
        let mut = try JSONEncoder.swooshDefault.encode(CronJobMutationResponse(job: job, message: "ok"))

        try await MockURLProtocol.with({ request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/cron"):
                return (200, ["Content-Type": "application/json"], list)
            case ("POST", "/api/cron"):
                let payload = try! JSONDecoder.swooshDefault.decode(CronJobCreateRequest.self, from: request.bodyData())
                #expect(payload.name == "standup")
                return (200, ["Content-Type": "application/json"], mut)
            case ("DELETE", "/api/cron/c-1"):
                return (200, ["Content-Type": "application/json"], list)
            case ("POST", "/api/cron/c-1/run"):
                return (200, ["Content-Type": "application/json"], mut)
            default:
                Issue.record("unexpected request: \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
                return (500, [:], Data())
            }
        }) {
            let client = makeClient()
            _ = try await client.cronJobs()
            _ = try await client.createCronJob(.init(name: "standup", prompt: "x", schedule: "daily"))
            _ = try await client.deleteCronJob(id: "c-1")
            _ = try await client.runCronJob(id: "c-1")
        }
    }

    // MARK: - Wallet ops

    @Test("Wallet account CRUD endpoints route correctly")
    func walletAccountMutations() async throws {
        let account = WalletAccountSummary(
            id: "w-1", chain: "solana", address: "abc...xyz",
            truncatedAddress: "abc…xyz", label: "main",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let list = try JSONEncoder.swooshDefault.encode(WalletAccountsResponse(accounts: [account]))
        let single = try JSONEncoder.swooshDefault.encode(WalletAccountResponse(account: account, message: "ok"))
        let balance = try JSONEncoder.swooshDefault.encode(WalletBalanceResponse(
            account: account, rawAmount: "1", formatted: "1 SOL",
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_100)
        ))

        try await MockURLProtocol.with({ request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/wallet/accounts"):
                return (200, ["Content-Type": "application/json"], list)
            case ("POST", "/api/wallet/accounts"):
                let payload = try! JSONDecoder.swooshDefault.decode(WalletCreateAccountRequest.self, from: request.bodyData())
                #expect(payload.chain == "solana")
                return (200, ["Content-Type": "application/json"], single)
            case ("DELETE", "/api/wallet/accounts/w-1"):
                return (200, ["Content-Type": "application/json"], list)
            case ("PATCH", "/api/wallet/accounts/w-1"):
                let payload = try! JSONDecoder.swooshDefault.decode(WalletRenameRequest.self, from: request.bodyData())
                #expect(payload.label == "treasury")
                return (200, ["Content-Type": "application/json"], single)
            case ("POST", "/api/wallet/accounts/w-1/balance"):
                return (200, ["Content-Type": "application/json"], balance)
            default:
                Issue.record("unexpected request: \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
                return (500, [:], Data())
            }
        }) {
            let client = makeClient()
            _ = try await client.walletAccounts()
            _ = try await client.createWalletAccount(.init(chain: "solana", label: "main"))
            _ = try await client.deleteWalletAccount(id: "w-1")
            _ = try await client.renameWalletAccount(id: "w-1", body: .init(label: "treasury"))
            _ = try await client.refreshWalletBalance(id: "w-1")
        }
    }

    // MARK: - Plugins

    @Test("Plugin endpoints route correctly")
    func pluginMutations() async throws {
        let plugin = PluginSummary(
            id: "ai.swoosh.demo.hello",
            name: "Hello", version: "0.1.0", description: nil, author: nil,
            kind: "swift", enabled: false, requestedPermissions: [],
            tools: [],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        let list = try JSONEncoder.swooshDefault.encode(PluginsResponse(plugins: [plugin]))
        let detail = try JSONEncoder.swooshDefault.encode(PluginDetailResponse(
            plugin: plugin, grantedPermissions: [], auditTail: []
        ))
        let mut = try JSONEncoder.swooshDefault.encode(PluginMutationResponse(plugin: plugin, message: "ok"))

        try await MockURLProtocol.with({ request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/plugins"):
                return (200, ["Content-Type": "application/json"], list)
            case ("GET", "/api/plugins/ai.swoosh.demo.hello"):
                return (200, ["Content-Type": "application/json"], detail)
            case ("POST", "/api/plugins/ai.swoosh.demo.hello/enable"),
                 ("POST", "/api/plugins/ai.swoosh.demo.hello/disable"):
                return (200, ["Content-Type": "application/json"], mut)
            case ("POST", "/api/plugins/install"):
                let payload = try! JSONDecoder.swooshDefault.decode(PluginInstallRequest.self, from: request.bodyData())
                #expect(payload.sourcePath == "/tmp/plugin-dir")
                return (200, ["Content-Type": "application/json"], mut)
            case ("DELETE", "/api/plugins/ai.swoosh.demo.hello"):
                return (200, ["Content-Type": "application/json"], list)
            default:
                Issue.record("unexpected request: \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
                return (500, [:], Data())
            }
        }) {
            let client = makeClient()
            _ = try await client.plugins()
            _ = try await client.plugin(id: "ai.swoosh.demo.hello")
            _ = try await client.enablePlugin(id: "ai.swoosh.demo.hello")
            _ = try await client.disablePlugin(id: "ai.swoosh.demo.hello")
            _ = try await client.installPlugin(sourcePath: "/tmp/plugin-dir")
            _ = try await client.uninstallPlugin(id: "ai.swoosh.demo.hello")
        }
    }
}
