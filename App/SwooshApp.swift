// App/SwooshApp.swift — Main Swoosh macOS application
//
// Menu bar app (no Dock icon) using MenuBarExtra.
// Surfaces the Swoosh command center as a popover from the system tray,
// exactly like CodexBar. Also hosts the widget data bridge.

import SwiftUI
import SwooshUI
import SwooshSecrets
import SwooshWidgets

@main
struct SwooshApp: App {
    @State private var menuBarManager = MenuBarManager(preset: .swoosh)
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        // ── Menu bar icon + popover ──
        MenuBarExtra {
            MenuBarPopoverView(manager: menuBarManager)
                .swooshTheme(themeManager.currentTheme)
                .onAppear {
                    Task { await menuBarManager.refreshCredentials() }
                }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        // ── Full dashboard window (Cmd+1 or "Open Dashboard") ──
        Window("Swoosh", id: "dashboard") {
            DashboardView()
        }
        .defaultSize(width: 1200, height: 800)

        // ── Settings window ──
        Settings {
            MenuBarCustomizerView(manager: menuBarManager)
                .swooshTheme(themeManager.currentTheme)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        switch menuBarManager.config.iconMode {
        case .swooshLogo:
            Image(systemName: "sparkles")
        case .providerMeter:
            Image(systemName: "chart.bar.fill")
        case .statusDot:
            Image(systemName: statusDotIcon)
        case .providerIcon:
            Image(systemName: "cloud.fill")
        case .custom:
            Image(systemName: menuBarManager.config.customIconName ?? "sparkles")
        }
    }

    private var statusDotIcon: String {
        let hasIssues = menuBarManager.providerStatuses.contains { !$0.isHealthy }
        return hasIssues ? "circle.fill" : "circle.fill"
    }
}
