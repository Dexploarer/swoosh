// Tests/SwooshToolsetsTests/CryptoRegistrationTests.swift
//
// Verifies that the crypto toolsets (EVM, Solana, Jupiter, Hyperliquid,
// Uniswap) are actually registered into a ToolRegistry by
// DefaultToolRegistrar.registerAll once concrete RPC clients are
// injected. Presence is checked via `getToolSchema` — which returns a
// registered tool regardless of catalog/policy visibility — so write
// tools (askEveryTime / humanOnly) count too. No tool is invoked, so
// nothing here touches the network.

import Testing
import Foundation
@testable import SwooshToolsets
@testable import SwooshTools
@testable import SwooshFirewall
@testable import SwooshFiles
@testable import SwooshProcess

// MARK: - Stub RPC clients (presence-only; throw on every call)

private struct StubEVMRPCClient: EVMRPCClient {
    func chainID(config: EVMRPCConfig) async throws -> EVMChainID { throw ToolError.executionFailed("stub") }
    func blockNumber(config: EVMRPCConfig) async throws -> EVMQuantity { throw ToolError.executionFailed("stub") }
    func getBalance(config: EVMRPCConfig, address: EVMAddress, block: EVMBlockParameter) async throws -> EVMQuantity { throw ToolError.executionFailed("stub") }
    func getTransactionCount(config: EVMRPCConfig, address: EVMAddress, block: EVMBlockParameter) async throws -> EVMQuantity { throw ToolError.executionFailed("stub") }
    func getCode(config: EVMRPCConfig, address: EVMAddress, block: EVMBlockParameter) async throws -> EVMHexData { throw ToolError.executionFailed("stub") }
    func call(config: EVMRPCConfig, call: EVMContractCallInput) async throws -> EVMHexData { throw ToolError.executionFailed("stub") }
    func estimateGas(config: EVMRPCConfig, tx: EVMTxEstimateGasInput) async throws -> EVMQuantity { throw ToolError.executionFailed("stub") }
    func getLogs(config: EVMRPCConfig, filter: EVMGetLogsInput) async throws -> [EVMLog] { throw ToolError.executionFailed("stub") }
    func sendRawTransaction(config: EVMRPCConfig, signedTransaction: EVMHexData) async throws -> EVMHexData { throw ToolError.executionFailed("stub") }
    func getTransactionReceipt(config: EVMRPCConfig, transactionHash: EVMHexData) async throws -> EVMTransactionReceipt? { throw ToolError.executionFailed("stub") }
    func getTransactionByHash(config: EVMRPCConfig, transactionHash: EVMHexData) async throws -> String? { throw ToolError.executionFailed("stub") }
}

private struct StubSolanaRPCClient: SolanaRPCClient {
    func getBalance(cluster: SolanaCluster, pubkey: SolanaPubkey, commitment: SolanaCommitment) async throws -> Lamports { throw ToolError.executionFailed("stub") }
    func getAccountInfo(cluster: SolanaCluster, input: SolanaAccountInfoInput) async throws -> SolanaAccountInfoOutput { throw ToolError.executionFailed("stub") }
    func getTokenAccountBalance(cluster: SolanaCluster, tokenAccount: SolanaPubkey, commitment: SolanaCommitment) async throws -> SolanaTokenAmount { throw ToolError.executionFailed("stub") }
    func getTokenAccountsByOwner(cluster: SolanaCluster, input: SolanaTokenAccountsByOwnerInput) async throws -> [SolanaTokenAccountEntry] { throw ToolError.executionFailed("stub") }
    func getSignaturesForAddress(cluster: SolanaCluster, input: SolanaSignaturesForAddressInput) async throws -> [SolanaSignatureInfo] { throw ToolError.executionFailed("stub") }
    func getTransaction(cluster: SolanaCluster, input: SolanaGetTransactionInput) async throws -> SolanaGetTransactionOutput { throw ToolError.executionFailed("stub") }
    func getSignatureStatuses(cluster: SolanaCluster, signatures: [SolanaSignature], searchTransactionHistory: Bool) async throws -> [SolanaSignatureStatus] { throw ToolError.executionFailed("stub") }
    func getLatestBlockhash(cluster: SolanaCluster, commitment: SolanaCommitment) async throws -> SolanaGetLatestBlockhashOutput { throw ToolError.executionFailed("stub") }
    func simulateTransaction(cluster: SolanaCluster, input: SolanaTxSimulateInput) async throws -> SolanaTxSimulateOutput { throw ToolError.executionFailed("stub") }
    func sendTransaction(cluster: SolanaCluster, input: SolanaTxSendSignedInput) async throws -> SolanaSignature { throw ToolError.executionFailed("stub") }
    func requestAirdrop(cluster: SolanaCluster, pubkey: SolanaPubkey, lamports: Lamports) async throws -> SolanaSignature { throw ToolError.executionFailed("stub") }
}

// MARK: - Harness with crypto clients injected

private func registerCryptoRegistry(withRPCClients: Bool) async -> ToolRegistry {
    let firewall = SwooshFirewallActor(granted: Set(SwooshPermission.allCases))
    let audit = SwooshAuditLog()
    let approvals = InMemoryApprovalRequester(autoApprove: true)
    let rootStore = InMemoryRootStore()
    let dependencies = ToolDependencies(
        firewall: firewall,
        audit: audit,
        approvals: approvals,
        fileAccess: SafeFileAccessor(rootStore: rootStore),
        processRunner: StreamingProcessRunner(),
        evmClient: withRPCClients ? StubEVMRPCClient() : nil,
        solanaClient: withRPCClients ? StubSolanaRPCClient() : nil
    )
    let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvals)
    await DefaultToolRegistrar.registerAll(into: registry, dependencies: dependencies)
    return registry
}

/// True if every named tool is present in the registry. `getToolSchema`
/// returns a registered tool regardless of catalog/policy visibility.
private func allRegistered(_ names: [String], in registry: ToolRegistry) async -> Bool {
    for name in names {
        if await registry.getToolSchema(name: ToolName(name)) == nil { return false }
    }
    return true
}

private func registeredCount(prefix: String, allNames: [String], in registry: ToolRegistry) async -> Int {
    var count = 0
    for name in allNames where name.hasPrefix(prefix) {
        if await registry.getToolSchema(name: ToolName(name)) != nil { count += 1 }
    }
    return count
}

// Full expected tool-name lists per family.
private let evmTools = [
    "evm.chain_info", "evm.address_validate", "evm.account_balance_native",
    "evm.account_nonce", "evm.contract_get_code", "evm.contract_call",
    "evm.contract_get_logs", "evm.erc20_balance", "evm.erc20_allowance",
    "evm.abi_encode_call", "evm.abi_decode_result", "evm.tx_estimate_gas",
    "evm.tx_preflight", "evm.tx_build_native_transfer", "evm.tx_build_contract_call",
    "evm.erc20_build_transfer", "evm.erc20_build_approve", "evm.wallet_connect",
    "evm.wallet_accounts", "evm.tx_request_signature", "evm.tx_broadcast_signed",
    "evm.tx_get_receipt", "evm.tx_get_by_hash",
]
private let solanaTools = [
    "solana.cluster_info", "solana.address_validate", "solana.account_balance",
    "solana.account_info", "solana.token_account_balance", "solana.token_accounts_by_owner",
    "solana.tx_signatures_for_address", "solana.tx_get_transaction",
    "solana.tx_get_signature_statuses", "solana.tx_get_latest_blockhash",
    "solana.tx_simulate", "solana.tx_build_sol_transfer", "solana.tx_build_spl_transfer",
    "solana.wallet_connect", "solana.wallet_accounts", "solana.tx_request_signature",
    "solana.tx_send_signed", "solana.tx_request_airdrop",
]
private let jupiterTools = [
    "jupiter.quote", "jupiter.swap", "jupiter.build_order", "jupiter.execute",
    "jupiter.balances", "jupiter.price", "jupiter.token_info", "jupiter.tradable_tokens",
    "jupiter.tokens.tagged", "jupiter.tokens.new", "jupiter.tokens.market_mints",
    "jupiter.tokens.all", "jupiter.shield", "jupiter.routers", "jupiter.dca.create",
    "jupiter.dca.list", "jupiter.dca.cancel", "jupiter.dca.price_deposit",
    "jupiter.dca.price_withdraw", "jupiter.limit_order.create",
    "jupiter.limit_order.list", "jupiter.limit_order.cancel",
]
private let hyperliquidTools = [
    "hyperliquid.all_mids", "hyperliquid.l2_book", "hyperliquid.user_state",
    "hyperliquid.open_orders", "hyperliquid.user_fills", "hyperliquid.limit_order",
    "hyperliquid.market_order", "hyperliquid.cancel_order", "hyperliquid.cancel_all",
    "hyperliquid.update_leverage",
]
private let uniswapTools = ["uniswap.quote", "uniswap.build_swap", "uniswap.pool_address"]

@Suite("Crypto toolset registration")
struct CryptoRegistrationTests {

    @Test("All 23 EVM tools register when an EVM RPC client is injected")
    func evmRegistersWithClient() async {
        let registry = await registerCryptoRegistry(withRPCClients: true)
        #expect(await allRegistered(evmTools, in: registry))
        #expect(await registeredCount(prefix: "evm.", allNames: evmTools, in: registry) == 23)
    }

    @Test("EVM tools are absent when no RPC client is injected")
    func evmAbsentWithoutClient() async {
        let registry = await registerCryptoRegistry(withRPCClients: false)
        #expect(await registry.getToolSchema(name: ToolName("evm.chain_info")) == nil)
        #expect(await registeredCount(prefix: "evm.", allNames: evmTools, in: registry) == 0)
    }

    @Test("All 18 Solana tools register when a Solana RPC client is injected")
    func solanaRegistersWithClient() async {
        let registry = await registerCryptoRegistry(withRPCClients: true)
        #expect(await allRegistered(solanaTools, in: registry))
        #expect(await registeredCount(prefix: "solana.", allNames: solanaTools, in: registry) == 18)
    }

    @Test("Solana tools are absent when no RPC client is injected")
    func solanaAbsentWithoutClient() async {
        let registry = await registerCryptoRegistry(withRPCClients: false)
        #expect(await registeredCount(prefix: "solana.", allNames: solanaTools, in: registry) == 0)
    }

    @Test("All 22 Jupiter tools register unconditionally (own HTTP client)")
    func jupiterRegistersUnconditionally() async {
        // Jupiter does not depend on the injected RPC clients.
        let withClients = await registerCryptoRegistry(withRPCClients: true)
        let withoutClients = await registerCryptoRegistry(withRPCClients: false)
        for registry in [withClients, withoutClients] {
            #expect(await allRegistered(jupiterTools, in: registry))
            #expect(await registeredCount(prefix: "jupiter.", allNames: jupiterTools, in: registry) == 22)
        }
    }

    @Test("All 10 Hyperliquid tools register unconditionally (own HTTP client)")
    func hyperliquidRegistersUnconditionally() async {
        let registry = await registerCryptoRegistry(withRPCClients: false)
        #expect(await allRegistered(hyperliquidTools, in: registry))
        #expect(await registeredCount(prefix: "hyperliquid.", allNames: hyperliquidTools, in: registry) == 10)
    }

    @Test("Uniswap tools register only when an EVM RPC client is injected")
    func uniswapGatedOnEVMClient() async {
        let withClients = await registerCryptoRegistry(withRPCClients: true)
        #expect(await allRegistered(uniswapTools, in: withClients))
        #expect(await registeredCount(prefix: "uniswap.", allNames: uniswapTools, in: withClients) == 3)

        let withoutClients = await registerCryptoRegistry(withRPCClients: false)
        #expect(await registeredCount(prefix: "uniswap.", allNames: uniswapTools, in: withoutClients) == 0)
    }

    @Test("Crypto write tools keep their permission + approval gates")
    func writeToolsStayGated() async {
        // Spot-check that the safety posture is unchanged: build/trade
        // tools remain permissioned and approval-gated.
        #expect(EVMERC20BuildTransferTool.permission == .evmBuildTransaction)
        #expect(EVMERC20BuildTransferTool.approval == .askEveryTime)
        #expect(EVMTxRequestSignatureTool.approval == .humanOnly)
        #expect(SolanaTxSendSignedTool.approval == .humanOnly)
        #expect(JupiterSwapTool.permission == .solanaBroadcast)
        #expect(JupiterSwapTool.approval == .askEveryTime)
        #expect(HLMarketOrderTool.permission == .hyperliquidTrade)
        #expect(HLMarketOrderTool.approval == .askEveryTime)
        #expect(UniswapSwapTool.approval == .askEveryTime)
    }
}
