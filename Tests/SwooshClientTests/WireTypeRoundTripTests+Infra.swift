// Tests/SwooshClientTests/WireTypeRoundTripTests+Infra.swift — 0.4A
//
// Round-trip Codable tests for the infrastructure tier-1 surfaces —
// MCP CRUD, firewall, cron, and wallet ops. Plus the plugin envelopes
// that the iOS app uses to render the installed-plugin catalog.

import Foundation
import Testing
@testable import SwooshClient

@Suite("Wire type round trips — Infra (MCP, firewall, cron, wallet, plugins)")
struct WireTypeRoundTripInfraTests {

    private let encoder = JSONEncoder.swooshDefault
    private let decoder = JSONDecoder.swooshDefault

    // MARK: - MCP CRUD

    @Test("MCPServerCreateRequest round-trips both stdio and http")
    func mcpServerCreateRequest() throws {
        let stdio = MCPServerCreateRequest(
            id: "pay",
            name: "Pay",
            description: "Paid HTTP",
            transport: "stdio",
            command: "/usr/local/bin/pay-mcp",
            arguments: ["--mode=mcp"],
            workingDirectory: "/tmp",
            environmentSecretRefs: ["PAY_API_KEY": "pay.api_key"],
            baseURL: nil,
            trustLevel: "userApproved",
            enabled: true
        )
        let http = MCPServerCreateRequest(
            id: "pay-http",
            name: "Pay HTTP",
            transport: "http",
            baseURL: "https://pay.example.com/mcp",
            authorizationSecretRef: "pay.api_key",
            localOnly: false,
            trustLevel: "userApproved",
            enabled: false
        )
        #expect(try decoder.decode(MCPServerCreateRequest.self, from: try encoder.encode(stdio)) == stdio)
        #expect(try decoder.decode(MCPServerCreateRequest.self, from: try encoder.encode(http)) == http)
    }

    @Test("MCPServerMutationResponse + MCPServerToolsResponse round-trip")
    func mcpMutationAndTools() throws {
        let summary = MCPServerRuntimeSummary(
            id: "pay",
            name: "Pay",
            description: nil,
            enabled: true,
            trustLevel: "userApproved",
            state: "connected",
            transport: "stdio",
            toolCount: 2,
            importedToolCount: 2,
            tools: [
                MCPDiscoveredToolSummary(id: "t-1", name: "pay.search", title: nil, description: nil, estimatedRisk: "readOnly"),
            ]
        )
        let mutation = MCPServerMutationResponse(server: summary, message: "added")
        let tools = MCPServerToolsResponse(serverID: "pay", tools: summary.tools)
        #expect(try decoder.decode(MCPServerMutationResponse.self, from: try encoder.encode(mutation)) == mutation)
        #expect(try decoder.decode(MCPServerToolsResponse.self, from: try encoder.encode(tools)) == tools)
    }

    // MARK: - Firewall

    @Test("Firewall request and response shapes round-trip")
    func firewallShapes() throws {
        let response = FirewallResponse(granted: ["solanaRead"], denied: ["solanaSendTransaction"])
        let grant = FirewallGrantRequest(permission: "solanaRead", decision: "grant")
        let mut = FirewallMutationResponse(firewall: response, message: "granted")
        let check = FirewallCheckRequest(permission: "solanaRead")
        let checkResp = FirewallCheckResponse(permission: "solanaRead", granted: true, denied: false)
        #expect(try decoder.decode(FirewallResponse.self, from: try encoder.encode(response)) == response)
        #expect(try decoder.decode(FirewallGrantRequest.self, from: try encoder.encode(grant)) == grant)
        #expect(try decoder.decode(FirewallMutationResponse.self, from: try encoder.encode(mut)) == mut)
        #expect(try decoder.decode(FirewallCheckRequest.self, from: try encoder.encode(check)) == check)
        #expect(try decoder.decode(FirewallCheckResponse.self, from: try encoder.encode(checkResp)) == checkResp)
    }

    // MARK: - Cron

    @Test("CronJobCreateRequest round-trips all optional fields")
    func cronCreate() throws {
        let value = CronJobCreateRequest(
            name: "daily standup",
            prompt: "Summarize yesterday",
            schedule: "daily at 9am",
            enabled: true,
            model: "swoosh-local-diagnostic-v1",
            provider: "local-diagnostic",
            skills: ["bundled.standup"],
            enabledToolsets: ["core"],
            workdir: "/Users/home/swoosh"
        )
        #expect(try decoder.decode(CronJobCreateRequest.self, from: try encoder.encode(value)) == value)
    }

    @Test("CronJobsResponse + mutation round-trip")
    func cronListAndMutation() throws {
        let job = CronJobRecordSummary(
            id: "c-1",
            name: "standup",
            state: "scheduled",
            enabled: true,
            nextRunAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastRunAt: nil
        )
        let list = CronJobsResponse(jobs: [job])
        let mut = CronJobMutationResponse(job: job, message: "created")
        #expect(try decoder.decode(CronJobsResponse.self, from: try encoder.encode(list)) == list)
        #expect(try decoder.decode(CronJobMutationResponse.self, from: try encoder.encode(mut)) == mut)
    }

    // MARK: - Wallet ops

    @Test("Wallet account CRUD round-trips")
    func walletAccountCRUD() throws {
        let account = WalletAccountSummary(
            id: "w-1",
            chain: "solana",
            address: "abc...xyz",
            truncatedAddress: "abc…xyz",
            label: "main",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let accounts = WalletAccountsResponse(accounts: [account])
        let create = WalletCreateAccountRequest(chain: "solana", label: "main")
        let rename = WalletRenameRequest(label: "treasury")
        let accountResp = WalletAccountResponse(account: account, message: "created")
        let balance = WalletBalanceResponse(
            account: account,
            rawAmount: "1000000000",
            formatted: "1.000000000 SOL",
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        #expect(try decoder.decode(WalletAccountsResponse.self, from: try encoder.encode(accounts)) == accounts)
        #expect(try decoder.decode(WalletCreateAccountRequest.self, from: try encoder.encode(create)) == create)
        #expect(try decoder.decode(WalletRenameRequest.self, from: try encoder.encode(rename)) == rename)
        #expect(try decoder.decode(WalletAccountResponse.self, from: try encoder.encode(accountResp)) == accountResp)
        #expect(try decoder.decode(WalletBalanceResponse.self, from: try encoder.encode(balance)) == balance)
    }

    // MARK: - Plugins

    @Test("Plugin summary + detail + mutation round-trip")
    func pluginShapes() throws {
        let tool = PluginToolSummary(
            name: "hello.swift.greet",
            description: "Say hi",
            permission: "toolRead",
            risk: "readOnly",
            requiresApproval: false
        )
        let plugin = PluginSummary(
            id: "ai.swoosh.demo.hello-swift",
            name: "Hello Swift",
            version: "0.1.0",
            description: "Demo Swift plugin",
            author: "Swoosh",
            kind: "swift",
            enabled: false,
            requestedPermissions: ["toolRead"],
            tools: [tool],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        let list = PluginsResponse(plugins: [plugin])
        let detail = PluginDetailResponse(
            plugin: plugin,
            grantedPermissions: ["toolRead"],
            auditTail: [
                PluginEventSummary(kind: "install", message: "installed", createdAt: Date(timeIntervalSince1970: 1_800_000_010)),
            ]
        )
        let install = PluginInstallRequest(sourcePath: "/Users/home/Plugins/HelloSwift")
        let mut = PluginMutationResponse(plugin: plugin, message: "ok")
        #expect(try decoder.decode(PluginsResponse.self, from: try encoder.encode(list)) == list)
        #expect(try decoder.decode(PluginDetailResponse.self, from: try encoder.encode(detail)) == detail)
        #expect(try decoder.decode(PluginInstallRequest.self, from: try encoder.encode(install)) == install)
        #expect(try decoder.decode(PluginMutationResponse.self, from: try encoder.encode(mut)) == mut)
    }
}
