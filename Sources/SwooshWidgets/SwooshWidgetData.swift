// SwooshWidgets/SwooshWidgetData.swift — Shared data model for widgets
//
// Lightweight, Codable models that bridge between the main app process
// and the widget extension sandbox. Data is shared via App Groups
// UserDefaults or a JSON file in the shared container.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - App Group constants
// ═══════════════════════════════════════════════════════════════════

public enum SwooshWidgetConstants {
    public static let appGroupIdentifier = "group.ai.swoosh.shared"
    public static let widgetDataKey = "swoosh_widget_data"
    public static let lastUpdateKey = "swoosh_widget_last_update"
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Widget data models
// ═══════════════════════════════════════════════════════════════════

/// Snapshot of a single provider's status for widget display.
public struct WidgetProviderStatus: Codable, Sendable, Identifiable, Hashable {
    public var id: String { providerID }

    public let providerID: String
    public let displayName: String
    public let sourceKind: String        // "ENV", "FILE", "KEY", "COOKIE"
    public let credentialKind: String     // "apiKey", "oauthToken", etc.
    public let isHealthy: Bool
    public let usagePercent: Double?      // 0.0–1.0 if available
    public let usageLabel: String?        // e.g. "45/100 requests"
    public let resetLabel: String?        // e.g. "Resets in 2h 15m"
    public let costLabel: String?         // e.g. "$4.23 / $10.00"

    public init(providerID: String, displayName: String,
                sourceKind: String, credentialKind: String,
                isHealthy: Bool = true, usagePercent: Double? = nil,
                usageLabel: String? = nil, resetLabel: String? = nil,
                costLabel: String? = nil) {
        self.providerID = providerID
        self.displayName = displayName
        self.sourceKind = sourceKind
        self.credentialKind = credentialKind
        self.isHealthy = isHealthy
        self.usagePercent = usagePercent
        self.usageLabel = usageLabel
        self.resetLabel = resetLabel
        self.costLabel = costLabel
    }
}

/// Full widget data snapshot shared between app and widget extension.
public struct SwooshWidgetSnapshot: Codable, Sendable {
    public let providers: [WidgetProviderStatus]
    public let pendingApprovals: Int
    public let activeAgents: Int
    public let activeBoardCards: Int
    public let activeWorkflows: Int
    public let totalCost: String?            // e.g. "$12.45"
    public let systemStatus: SystemStatus
    public let timestamp: Date

    public enum SystemStatus: String, Codable, Sendable {
        case healthy
        case degraded
        case offline
    }

    public init(providers: [WidgetProviderStatus] = [],
                pendingApprovals: Int = 0,
                activeAgents: Int = 0,
                activeBoardCards: Int = 0,
                activeWorkflows: Int = 0,
                totalCost: String? = nil,
                systemStatus: SystemStatus = .healthy,
                timestamp: Date = Date()) {
        self.providers = providers
        self.pendingApprovals = pendingApprovals
        self.activeAgents = activeAgents
        self.activeBoardCards = activeBoardCards
        self.activeWorkflows = activeWorkflows
        self.totalCost = totalCost
        self.systemStatus = systemStatus
        self.timestamp = timestamp
    }

    // ── Serialization for App Group ──

    /// Write to shared UserDefaults.
    public func save(to userDefaults: UserDefaults? = nil) {
        let defaults = userDefaults ?? UserDefaults(suiteName: SwooshWidgetConstants.appGroupIdentifier)
        guard let defaults else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) {
            defaults.set(data, forKey: SwooshWidgetConstants.widgetDataKey)
            defaults.set(Date(), forKey: SwooshWidgetConstants.lastUpdateKey)
        }
    }

    /// Read from shared UserDefaults.
    public static func load(from userDefaults: UserDefaults? = nil) -> SwooshWidgetSnapshot? {
        let defaults = userDefaults ?? UserDefaults(suiteName: SwooshWidgetConstants.appGroupIdentifier)
        guard let defaults,
              let data = defaults.data(forKey: SwooshWidgetConstants.widgetDataKey)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SwooshWidgetSnapshot.self, from: data)
    }

    /// Sample data for widget previews.
    public static var preview: SwooshWidgetSnapshot {
        SwooshWidgetSnapshot(
            providers: [
                WidgetProviderStatus(providerID: "openai", displayName: "OpenAI",
                                     sourceKind: "ENV", credentialKind: "apiKey",
                                     usagePercent: 0.45, usageLabel: "45%",
                                     resetLabel: "Resets in 3h", costLabel: "$4.23"),
                WidgetProviderStatus(providerID: "openrouter", displayName: "OpenRouter",
                                     sourceKind: "KEY", credentialKind: "apiKey",
                                     usagePercent: 0.72, usageLabel: "72%",
                                     resetLabel: "Resets in 1h 30m", costLabel: "$8.10"),
                WidgetProviderStatus(providerID: "detour-cloud", displayName: "Detour Cloud",
                                     sourceKind: "FILE", credentialKind: "apiKey",
                                     usagePercent: 0.18, usageLabel: "18%"),
                WidgetProviderStatus(providerID: "mlx-local", displayName: "MLX Local",
                                     sourceKind: "LOCAL", credentialKind: "none",
                                     usagePercent: 0.90, usageLabel: "90%",
                                     resetLabel: nil, costLabel: "$0.00"),
            ],
            pendingApprovals: 3,
            activeAgents: 2,
            activeBoardCards: 7,
            activeWorkflows: 1,
            totalCost: "$13.38",
            systemStatus: .healthy
        )
    }
}
