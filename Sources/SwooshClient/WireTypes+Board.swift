// SwooshClient/WireTypes+Board.swift — 0.4A Board and metrics wire types
//
// Even though the standalone `SwooshBoard` module was retired, the
// `/api/board/*` endpoints are still produced by `SwooshAPI`'s runtime
// board projection and consumed by `SwooshUI.DashboardView`. These wire
// types keep the contract typed.

import Foundation

public struct BoardLaneSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let cardCount: Int

    public init(id: String, title: String, cardCount: Int) {
        self.id = id
        self.title = title
        self.cardCount = cardCount
    }
}

public struct BoardCardSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let laneID: String
    public let title: String
    public let detail: String
    public let updatedAt: Date

    public init(id: String, laneID: String, title: String, detail: String, updatedAt: Date = Date()) {
        self.id = id
        self.laneID = laneID
        self.title = title
        self.detail = detail
        self.updatedAt = updatedAt
    }
}

public struct BoardLanesResponse: Codable, Sendable {
    public let lanes: [BoardLaneSummary]

    public init(lanes: [BoardLaneSummary]) {
        self.lanes = lanes
    }
}

public struct BoardCardsResponse: Codable, Sendable {
    public let cards: [BoardCardSummary]

    public init(cards: [BoardCardSummary]) {
        self.cards = cards
    }
}

public struct MetricCounter: Codable, Sendable, Identifiable {
    public let id: String
    public let value: Int

    public init(id: String, value: Int) {
        self.id = id
        self.value = value
    }
}

public struct MetricsResponse: Codable, Sendable {
    public let counters: [MetricCounter]
    public let generatedAt: Date

    public init(counters: [MetricCounter], generatedAt: Date = Date()) {
        self.counters = counters
        self.generatedAt = generatedAt
    }
}
