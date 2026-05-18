// SwooshWidgets/ControlCenter/SwooshControlWidget.swift — Control Center toggle
//
// macOS 26 Control Center widget. Shows quick status and provides
// a one-tap toggle to refresh provider discovery.

import SwiftUI
import WidgetKit
import AppIntents
import SwooshSecrets

// ═══════════════════════════════════════════════════════════════════
// MARK: - Control Center widget
// ═══════════════════════════════════════════════════════════════════

/// A Control Center button that shows provider count and triggers refresh.
@available(macOS 26.0, *)
public struct SwooshControlWidget: ControlWidget {
    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ai.swoosh.control") {
            ControlWidgetButton(action: RefreshProvidersIntent()) {
                Label {
                    Text("Swoosh")
                    Text(statusText)
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
        }
        .displayName("Swoosh")
        .description("Quick provider status and refresh.")
    }

    private var statusText: String {
        let snapshot = SwooshWidgetSnapshot.load()
        let count = snapshot?.providers.count ?? 0
        return "\(count) providers"
    }
}

/// Intent that refreshes provider discovery from Control Center.
@available(macOS 26.0, *)
struct RefreshProvidersIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Providers"
    static let description = IntentDescription("Refreshes AI provider credential discovery.")

    func perform() async throws -> some IntentResult {
        // Run discovery and push to widget
        WidgetDataBridge.pushUpdate()
        return .result()
    }
}
