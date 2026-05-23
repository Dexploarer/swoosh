// SwooshClient/WireTypes+Wallet.swift — 0.4A Wallet dashboard + account CRUD
//
// Carries the analytics/asset projections behind `GET /api/wallet` (the
// dashboard) and the account-level CRUD types for `GET/POST/PATCH/DELETE
// /api/wallet/accounts*`. All money values are strings — never `Double` —
// to preserve exact precision across the wire.

import Foundation

public struct WalletAnalyticsSummary: Codable, Sendable, Equatable {
    public let totalValueUSD: String?
    public let realizedPnLUSD: String?
    public let unrealizedPnLUSD: String?
    public let totalPnLPercent: String?
    public let dailyChangePercent: String?
    public let openPositions: Int

    public init(
        totalValueUSD: String?,
        realizedPnLUSD: String?,
        unrealizedPnLUSD: String?,
        totalPnLPercent: String?,
        dailyChangePercent: String?,
        openPositions: Int
    ) {
        self.totalValueUSD = totalValueUSD
        self.realizedPnLUSD = realizedPnLUSD
        self.unrealizedPnLUSD = unrealizedPnLUSD
        self.totalPnLPercent = totalPnLPercent
        self.dailyChangePercent = dailyChangePercent
        self.openPositions = openPositions
    }
}

public struct WalletAssetSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let chain: String
    public let symbol: String
    public let name: String?
    public let quantity: String
    public let valueUSD: String?
    public let costBasisUSD: String?
    public let pnlUSD: String?
    public let pnlPercent: String?

    public init(
        id: String,
        chain: String,
        symbol: String,
        name: String?,
        quantity: String,
        valueUSD: String?,
        costBasisUSD: String?,
        pnlUSD: String?,
        pnlPercent: String?
    ) {
        self.id = id
        self.chain = chain
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.valueUSD = valueUSD
        self.costBasisUSD = costBasisUSD
        self.pnlUSD = pnlUSD
        self.pnlPercent = pnlPercent
    }
}

public enum WalletInsightSeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}

public struct WalletInsightSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let severity: WalletInsightSeverity
    public let title: String
    public let detail: String
    public let source: String

    public init(id: String, severity: WalletInsightSeverity, title: String, detail: String, source: String) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.source = source
    }
}

public struct WalletTradingCapabilitySummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let enabled: Bool
    public let configured: Bool
    public let status: String
    public let risk: String

    public init(id: String, name: String, enabled: Bool, configured: Bool, status: String, risk: String) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.configured = configured
        self.status = status
        self.risk = risk
    }
}

public struct WalletDashboardResponse: Codable, Sendable, Equatable {
    public let connected: Bool
    public let walletLabel: String?
    public let analytics: WalletAnalyticsSummary
    public let assets: [WalletAssetSummary]
    public let insights: [WalletInsightSummary]
    public let capabilities: [WalletTradingCapabilitySummary]
    public let generatedAt: Date

    public init(
        connected: Bool,
        walletLabel: String?,
        analytics: WalletAnalyticsSummary,
        assets: [WalletAssetSummary],
        insights: [WalletInsightSummary],
        capabilities: [WalletTradingCapabilitySummary],
        generatedAt: Date = Date()
    ) {
        self.connected = connected
        self.walletLabel = walletLabel
        self.analytics = analytics
        self.assets = assets
        self.insights = insights
        self.capabilities = capabilities
        self.generatedAt = generatedAt
    }
}

public struct WalletAccountSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let chain: String
    public let address: String
    public let truncatedAddress: String
    public let label: String
    public let createdAt: Date

    public init(
        id: String,
        chain: String,
        address: String,
        truncatedAddress: String,
        label: String,
        createdAt: Date
    ) {
        self.id = id
        self.chain = chain
        self.address = address
        self.truncatedAddress = truncatedAddress
        self.label = label
        self.createdAt = createdAt
    }
}

public struct WalletAccountsResponse: Codable, Sendable, Equatable {
    public let accounts: [WalletAccountSummary]

    public init(accounts: [WalletAccountSummary]) {
        self.accounts = accounts
    }
}

public struct WalletCreateAccountRequest: Codable, Sendable, Equatable {
    public let chain: String
    public let label: String

    public init(chain: String, label: String) {
        self.chain = chain
        self.label = label
    }
}

public struct WalletRenameRequest: Codable, Sendable, Equatable {
    public let label: String

    public init(label: String) {
        self.label = label
    }
}

public struct WalletAccountResponse: Codable, Sendable, Equatable {
    public let account: WalletAccountSummary
    public let message: String

    public init(account: WalletAccountSummary, message: String) {
        self.account = account
        self.message = message
    }
}

public struct WalletBalanceResponse: Codable, Sendable, Equatable {
    public let account: WalletAccountSummary
    public let rawAmount: String
    public let formatted: String
    public let fetchedAt: Date

    public init(
        account: WalletAccountSummary,
        rawAmount: String,
        formatted: String,
        fetchedAt: Date
    ) {
        self.account = account
        self.rawAmount = rawAmount
        self.formatted = formatted
        self.fetchedAt = fetchedAt
    }
}
