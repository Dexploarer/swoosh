// SwooshWidgetsTests/WidgetDataTests.swift — Widget snapshot persistence tests

import XCTest
@testable import SwooshWidgets

final class SwooshWidgetDataTests: XCTestCase {
    func testSnapshotSavesAndLoadsFromUserDefaults() {
        let suiteName = "ai.swoosh.tests.widgets.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let snapshot = SwooshWidgetSnapshot(
            providers: [
                WidgetProviderStatus(
                    providerID: "openai",
                    displayName: "OpenAI",
                    sourceKind: "KEY",
                    credentialKind: "apiKey",
                    isHealthy: true,
                    usagePercent: 0.42,
                    usageLabel: "42%"
                ),
            ],
            pendingApprovals: 2,
            activeAgents: 1,
            activeBoardCards: 3,
            activeWorkflows: 4,
            totalCost: "$1.23",
            systemStatus: .healthy,
            timestamp: Date(timeIntervalSince1970: 1_776_000_000)
        )

        snapshot.save(to: defaults)
        let loaded = SwooshWidgetSnapshot.load(from: defaults)

        XCTAssertEqual(loaded?.providers.first?.providerID, "openai")
        XCTAssertEqual(loaded?.providers.first?.usagePercent, 0.42)
        XCTAssertEqual(loaded?.pendingApprovals, 2)
        XCTAssertEqual(loaded?.activeWorkflows, 4)
        XCTAssertEqual(loaded?.totalCost, "$1.23")
        XCTAssertEqual(loaded?.systemStatus, .healthy)
    }
}
