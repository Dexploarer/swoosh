#if os(macOS)

// SwooshUI/Interactions/FocusedTab.swift — FocusedValue for active tab
//
// Publishes the currently selected DashboardTab through the SwiftUI
// focused-value system so that Commands structs (menu bar items) can
// observe it and render context-aware menus.

import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Focused value key
// ═══════════════════════════════════════════════════════════════════

private struct FocusedDashboardTabKey: FocusedValueKey {
    typealias Value = DashboardTab
}

public extension FocusedValues {
    var activeDashboardTab: DashboardTab? {
        get { self[FocusedDashboardTabKey.self] }
        set { self[FocusedDashboardTabKey.self] = newValue }
    }
}

#endif
