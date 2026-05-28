// SwooshAPI/APIHelpers.swift — 0.9S Shared route + runtime helpers
//
// Pure functions used by both `SwooshAPIServer.build()` and the
// `APIRuntimeState` actor: error translation, runtime-config wire-format
// builders, default wallet-dashboard payload for when no bridge is wired.

import Foundation
import Hummingbird
import SwooshClient
import SwooshConfig
import SwooshChatSDK
import SwooshTools

func makeChatAdaptersResponse(
    catalog: ChatAdapterCatalog,
    store: ChatAdapterToggleStore,
    stateCatalog: ChatStateAdapterCatalog,
    stateStore: ChatStateAdapterToggleStore
) async throws -> ChatAdaptersResponse {
    let statuses = try await catalog.statuses(store: store)
    let stateStatuses = try await stateCatalog.statuses(store: stateStore)
    return ChatAdapterProjection.response(platformStatuses: statuses, stateStatuses: stateStatuses)
}

func apiHTTPError(_ error: Error) -> HTTPError {
    if let apiError = error as? APIError {
        switch apiError {
        case .notFound(let message):
            return HTTPError(.notFound, message: message)
        case .unauthorized:
            return HTTPError(.unauthorized, message: "unauthorized")
        case .badRequest(let message):
            return HTTPError(.badRequest, message: message)
        case .internalError(let message):
            return HTTPError(.internalServerError, message: message)
        }
    }
    return HTTPError(.internalServerError, message: error.localizedDescription)
}

/// Returns the current quarter period string, e.g. "2026-Q2".
/// Matches the format used by `RebateTracker.currentPeriod()`.
func currentQuarterPeriod() -> String {
    let cal = Calendar.current; let now = Date()
    let year = cal.component(.year, from: now)
    let quarter = (cal.component(.month, from: now) - 1) / 3 + 1
    return "\(year)-Q\(quarter)"
}

func runtimeConfigResponse(_ config: SwooshRuntimeConfig?) -> RuntimeConfigResponse {
    guard let config else {
        return RuntimeConfigResponse(
            configured: false,
            setupMode: nil,
            permissionProfile: nil,
            modelPath: nil,
            daemonHost: nil,
            daemonPort: nil,
            preferredProviderID: nil,
            localDiagnosticFallback: false,
            toolPolicy: nil,
            safetyFlags: []
        )
    }
    let policy = config.toolPolicy
    return RuntimeConfigResponse(
        configured: true,
        setupMode: config.setupMode,
        permissionProfile: config.permissionProfile,
        modelPath: config.modelPath,
        daemonHost: config.daemonHost,
        daemonPort: config.daemonPort,
        preferredProviderID: config.preferredProviderID,
        localDiagnosticFallback: config.localDiagnosticFallback,
        toolPolicy: ToolPolicySummary(
            maxToolCallsPerTurn: policy.maxToolCallsPerTurn,
            maxToolChainDepth: policy.maxToolChainDepth,
            allowModelToolCalls: policy.allowModelToolCalls,
            allowHumanOnlyFromModel: policy.allowHumanOnlyFromModel,
            allowCriticalToolsFromModel: policy.allowCriticalToolsFromModel,
            requireApprovalForMediumRiskAndAbove: policy.requireApprovalForMediumRiskAndAbove
        ),
        safetyFlags: safetyFlagSummaries(config.safetyConfig)
    )
}

func safetyFlagSummaries(_ config: SwooshSafetyConfig) -> [RuntimeFlagSummary] {
    [
        RuntimeFlagSummary(id: "autonomousTradingEnabled", label: "Autonomous trading", enabled: config.autonomousTradingEnabled),
        RuntimeFlagSummary(id: "humanPromptedTradingEnabled", label: "Human-prompted trading", enabled: config.humanPromptedTradingEnabled),
        RuntimeFlagSummary(id: "swapExecutionEnabled", label: "Swap execution", enabled: config.swapExecutionEnabled),
        RuntimeFlagSummary(id: "portfolioRecommendationsEnabled", label: "Portfolio recommendations", enabled: config.portfolioRecommendationsEnabled),
        RuntimeFlagSummary(id: "privateKeyCustodyEnabled", label: "Private-key custody", enabled: config.privateKeyCustodyEnabled),
        RuntimeFlagSummary(id: "seedPhraseIngestionEnabled", label: "Seed phrase ingestion", enabled: config.seedPhraseIngestionEnabled),
        RuntimeFlagSummary(id: "cookieIngestionEnabled", label: "Cookie ingestion", enabled: config.cookieIngestionEnabled),
        RuntimeFlagSummary(id: "shellToBlockchainBridgeEnabled", label: "Shell to blockchain bridge", enabled: config.shellToBlockchainBridgeEnabled),
        RuntimeFlagSummary(id: "modelSelfApprovalEnabled", label: "Model self-approval", enabled: config.modelSelfApprovalEnabled),
        RuntimeFlagSummary(id: "mainnetWritesByDefault", label: "Mainnet writes by default", enabled: config.mainnetWritesByDefault),
    ]
}

func defaultWalletDashboard(config: SwooshRuntimeConfig?) -> WalletDashboardResponse {
    let safety = config?.safetyConfig ?? .defaultAgent
    let permissions = PermissionProfilePreset(rawValue: config?.permissionProfile ?? "")?.grantedSwooshPermissions ?? []
    let promptedTradingEnabled = safety.humanPromptedTradingEnabled || safety.autonomousTradingEnabled
    let tradingEnabled = promptedTradingEnabled && permissions.contains(.hyperliquidTrade)
    let swapsEnabled = promptedTradingEnabled && safety.swapExecutionEnabled
        && (permissions.contains(.evmBuildTransaction) || permissions.contains(.solanaBuildTransaction))
    let portfolioEnabled = safety.portfolioRecommendationsEnabled
    let mainnetEnabled = safety.mainnetWritesByDefault
        && permissions.contains(.evmMainnetWrite)
        && permissions.contains(.solanaMainnetWrite)
    return WalletDashboardResponse(
        connected: false,
        walletLabel: nil,
        analytics: WalletAnalyticsSummary(
            totalValueUSD: nil,
            realizedPnLUSD: nil,
            unrealizedPnLUSD: nil,
            totalPnLPercent: nil,
            dailyChangePercent: nil,
            openPositions: 0
        ),
        assets: [],
        insights: [
            WalletInsightSummary(
                id: "wallet.not_connected",
                severity: .warning,
                title: "No wallet connected",
                detail: "Wallet analytics and PnL stay empty until a wallet bridge or account source is connected.",
                source: "runtime"
            ),
        ],
        capabilities: [
            WalletTradingCapabilitySummary(
                id: "trading.human_prompted",
                name: "Human-prompted trading",
                enabled: safety.humanPromptedTradingEnabled,
                configured: true,
                status: safety.humanPromptedTradingEnabled ? "approval_required" : "disabled_by_safety_flag",
                risk: "critical"
            ),
            WalletTradingCapabilitySummary(
                id: "mainnet.write",
                name: "Mainnet writes",
                enabled: mainnetEnabled,
                configured: permissions.contains(.evmMainnetWrite) || permissions.contains(.solanaMainnetWrite),
                status: mainnetEnabled ? "mainnet_enabled" : "requires_trader_or_autonomous_profile",
                risk: "critical"
            ),
            WalletTradingCapabilitySummary(
                id: "portfolio",
                name: "Portfolio insights",
                enabled: portfolioEnabled,
                configured: portfolioEnabled,
                status: portfolioEnabled ? "enabled" : "disabled_by_safety_flag",
                risk: "medium"
            ),
            WalletTradingCapabilitySummary(
                id: "swaps",
                name: "DEX swaps",
                enabled: swapsEnabled,
                configured: false,
                status: swapsEnabled ? "waiting_for_wallet" : "disabled_by_config",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "pay.api_wallet",
                name: "Pay API wallet",
                enabled: permissions.contains(.mcpExecute),
                configured: false,
                status: "requires_pay_cli_or_mcp",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "pancakeswap.planner",
                name: "PancakeSwap planner",
                enabled: true,
                configured: true,
                status: "bundled_skill_deeplinks",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "launchpads.solana",
                name: "Solana launchpads",
                enabled: true,
                configured: true,
                status: "pumpportal_bags_skills",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "launchpads.bnb",
                name: "BNB launchpads",
                enabled: true,
                configured: true,
                status: "flap_fourmeme_skills",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "hyperliquid",
                name: "Hyperliquid trading",
                enabled: tradingEnabled,
                configured: false,
                status: tradingEnabled ? "waiting_for_secret_ref" : "disabled_by_config",
                risk: "critical"
            ),
        ]
    )
}
