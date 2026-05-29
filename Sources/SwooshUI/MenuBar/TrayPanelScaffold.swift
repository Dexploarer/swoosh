// SwooshUI/MenuBar/TrayPanelScaffold.swift — 0.1A Shared tray-panel chrome
//
// Header + scrollable body + optional "Open in Detour" footer for the
// menu-bar tray panels (Cloud / Wallet / Calendar). Neon-line language on a
// pure-black canvas. "Open in Detour" focuses the dashboard window and
// navigates it via the canonical `.swooshNavigateTab` notification (owned by
// MenuActionHandler) — the tray never introduces a second navigation lane.

#if os(macOS)

import SwiftUI
import AppKit
import SwooshGenerativeUI

/// Focus the main dashboard window and select a tab by its `DashboardTab`
/// rawValue, reusing the canonical `.swooshNavigateTab` lane. The dashboard
/// window may be (re)mounting, so the post is deferred a beat to let its
/// receiver attach.
@MainActor
func openDetourTab(_ rawValue: String, using openWindow: OpenWindowAction) {
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: "dashboard")
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(200))
        NotificationCenter.default.post(name: .swooshNavigateTab, object: rawValue)
    }
}

/// A 0.5pt neon divider, matching DashboardView's sidebar rule.
struct TrayHairline: View {
    var body: some View {
        Rectangle()
            .fill(SwooshNeonTokens.Line.rule)
            .frame(height: 0.5)
    }
}

struct TrayPanelScaffold<PanelBody: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: NeonAccent
    /// `DashboardTab` rawValue to open, or `nil` to hide the footer button.
    var openTab: String? = nil
    @ViewBuilder var content: () -> PanelBody

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TrayHairline()
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            if let openTab {
                TrayHairline()
                footer(openTab)
            }
        }
        .background(SwooshNeonTokens.Canvas.bg)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent.color)
                .neonGlow(accent, intensity: SwooshNeonTokens.Glow.focus)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func footer(_ tab: String) -> some View {
        Button {
            openDetourTab(tab, using: openWindow)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10, weight: .semibold))
                Text("Open in Detour")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(accent.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(8)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Small reusable rows
// ═══════════════════════════════════════════════════════════════════

/// A status banner used by panels for loading / empty / error states.
struct TrayStatusRow: View {
    let icon: String
    let message: String
    var accent: NeonAccent = .cyan
    var spinning: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if spinning {
                ProgressView()
                    .controlSize(.small)
                    .tint(accent.color)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent.color)
            }
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neonTile(accent, state: .idle, shape: .card)
    }
}

/// Section label — small caps, dim, with a hairline-style weight.
struct TraySectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
    }
}

#endif
