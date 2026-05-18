// SwooshWidgets/WidgetDataBridge.swift — Bridge between main app and widget extension
//
// The main Swoosh app calls WidgetDataBridge.update() to push fresh data
// into the App Group shared container. The widget extension reads it
// via SwooshWidgetSnapshot.load().

import Foundation
import WidgetKit
import SwooshSecrets

public enum WidgetDataBridge {

    /// Build a fresh snapshot from the current credential scavenger state
    /// and push it to the widget.
    public static func pushUpdate(
        pendingApprovals: Int = 0,
        activeAgents: Int = 0,
        activeBoardCards: Int = 0,
        activeWorkflows: Int = 0,
        totalCost: String? = nil,
        systemStatus: SwooshWidgetSnapshot.SystemStatus = .healthy
    ) {
        let discovered = CredentialScavenger.discoverAll()

        let providers = discovered.map { cred in
            WidgetProviderStatus(
                providerID: cred.provider.rawValue,
                displayName: cred.provider.displayName,
                sourceKind: sourceLabel(cred.source),
                credentialKind: cred.credentialKind.rawValue,
                isHealthy: true
            )
        }

        let snapshot = SwooshWidgetSnapshot(
            providers: providers,
            pendingApprovals: pendingApprovals,
            activeAgents: activeAgents,
            activeBoardCards: activeBoardCards,
            activeWorkflows: activeWorkflows,
            totalCost: totalCost,
            systemStatus: systemStatus
        )

        snapshot.save()

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Push a pre-built snapshot directly.
    public static func pushSnapshot(_ snapshot: SwooshWidgetSnapshot) {
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func sourceLabel(_ source: CredentialSource) -> String {
        switch source {
        case .environment:        return "ENV"
        case .configFile:         return "FILE"
        case .keychainThirdParty: return "KEY"
        case .browserCookie:      return "COOKIE"
        case .swooshKeychain:     return "SWOOSH"
        }
    }
}
