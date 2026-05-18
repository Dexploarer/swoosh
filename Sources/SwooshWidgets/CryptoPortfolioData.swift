// SwooshWidgets/CryptoPortfolioData.swift
// Portfolio data models for the Swoosh menu bar and widget — inspired by
// CryptoBar (https://github.com/Cmalf-Labs/CryptoBar) and
// mac-widget (https://github.com/mpavic1/mac-widget) patterns.
//
// Fetches prices from DexScreener (free, no auth) and CoinGecko.
// All network calls are read-only. No keys stored here.

import Foundation

// MARK: - Token price snapshot

public struct TokenPriceSnapshot: Codable, Sendable, Identifiable, Hashable {
    public var id: String { mint }
    public let mint: String          // SPL mint or "SOL"
    public let symbol: String
    public let name: String
    public let priceUSD: Double
    public let change24hPct: Double  // signed percentage
    public let volumeUSD24h: Double?
    public let marketCapUSD: Double?
    public let updatedAt: Date

    public var isPositive: Bool { change24hPct >= 0 }
    public var changeLabel: String {
        let sign = isPositive ? "+" : ""
        return "\(sign)\(String(format: "%.2f", change24hPct))%"
    }
    public var priceLabel: String { "$\(String(format: "%.4f", priceUSD))" }
}

// MARK: - Portfolio entry

public struct PortfolioEntry: Codable, Sendable, Identifiable {
    public var id: String { mint }
    public let mint: String
    public let symbol: String
    public let balance: Double       // token units
    public let price: TokenPriceSnapshot?

    public var valueUSD: Double? {
        guard let p = price else { return nil }
        return balance * p.priceUSD
    }
    public var valueLabel: String {
        guard let v = valueUSD else { return "--" }
        return "$\(String(format: "%.2f", v))"
    }
}

// MARK: - Portfolio snapshot (for App Group sharing)

public struct CryptoPortfolioSnapshot: Codable, Sendable {
    public let entries: [PortfolioEntry]
    public let totalValueUSD: Double?
    public let walletAddress: String?
    public let timestamp: Date

    public var totalValueLabel: String {
        guard let t = totalValueUSD else { return "--" }
        return "$\(String(format: "%.2f", t))"
    }

    public init(entries: [PortfolioEntry] = [], walletAddress: String? = nil, timestamp: Date = Date()) {
        self.entries = entries
        self.walletAddress = walletAddress
        self.timestamp = timestamp
        self.totalValueUSD = entries.compactMap(\.valueUSD).reduce(0, +)
    }

    /// Save to App Group UserDefaults
    public func save() {
        let defaults = UserDefaults(suiteName: SwooshWidgetConstants.appGroupIdentifier)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) {
            defaults?.set(data, forKey: "swoosh_portfolio_snapshot")
        }
    }

    /// Load from App Group UserDefaults
    public static func load() -> CryptoPortfolioSnapshot? {
        guard let data = UserDefaults(suiteName: SwooshWidgetConstants.appGroupIdentifier)?
            .data(forKey: "swoosh_portfolio_snapshot") else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CryptoPortfolioSnapshot.self, from: data)
    }
}

// MARK: - DexScreener price fetcher (mac-widget pattern)

public actor DexScreenerPriceFetcher {
    static let baseURL = "https://api.dexscreener.com/latest/dex/tokens/"

    public init() {}

    /// Fetch price for a list of token mints (comma-separated, up to 30)
    public func fetchPrices(mints: [String]) async throws -> [TokenPriceSnapshot] {
        guard !mints.isEmpty else { return [] }
        let joined = mints.prefix(30).joined(separator: ",")
        guard let url = URL(string: Self.baseURL + joined) else { throw PriceFetchError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PriceFetchError.httpError
        }

        let decoded = try JSONDecoder().decode(DexScreenerResponse.self, from: data)
        let now = Date()

        // Group by base token address, take the highest-liquidity pair per token
        var best: [String: DexPair] = [:]
        for pair in decoded.pairs ?? [] {
            let addr = pair.baseToken?.address ?? ""
            if let existing = best[addr] {
                let newLiq = pair.liquidity?.usd ?? 0
                let existLiq = existing.liquidity?.usd ?? 0
                if newLiq > existLiq { best[addr] = pair }
            } else {
                best[addr] = pair
            }
        }

        return best.values.map { pair in
            TokenPriceSnapshot(
                mint: pair.baseToken?.address ?? "",
                symbol: pair.baseToken?.symbol ?? "?",
                name: pair.baseToken?.name ?? "",
                priceUSD: Double(pair.priceUsd ?? "0") ?? 0,
                change24hPct: pair.priceChange?.h24 ?? 0,
                volumeUSD24h: pair.volume?.h24,
                marketCapUSD: pair.marketCap,
                updatedAt: now
            )
        }
    }
}

// MARK: - DexScreener response models (minimal)

private struct DexScreenerResponse: Codable {
    let pairs: [DexPair]?
}

private struct DexPair: Codable {
    let baseToken: DexToken?
    let priceUsd: String?
    let priceChange: PriceChange?
    let volume: Volume?
    let liquidity: Liquidity?
    let marketCap: Double?
}

private struct DexToken: Codable {
    let address: String
    let symbol: String
    let name: String
}

private struct PriceChange: Codable {
    let h24: Double?
    let h6: Double?
    let h1: Double?
}

private struct Volume: Codable {
    let h24: Double?
}

private struct Liquidity: Codable {
    let usd: Double?
}

public enum PriceFetchError: Error {
    case invalidURL
    case httpError
    case parseError
}
