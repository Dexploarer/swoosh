// SwooshUI/Gaming/GameWindowPicker.swift — Game window selection — 0.9T
//
// A SwiftUI view for selecting a game window to capture.
// ScreenCaptureKit integration will populate the window list later;
// for now the view shows the input pattern with mock placeholder rows.

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Game window picker
// ═══════════════════════════════════════════════════════════════════

public struct GameWindowPicker: View {

    @Binding public var windowTitle: String
    @Binding public var bundleID: String

    @State private var searchText: String = ""
    @State private var mockWindows: [MockWindow] = MockWindow.placeholders

    public init(windowTitle: Binding<String>, bundleID: Binding<String>) {
        self._windowTitle = windowTitle
        self._bundleID = bundleID
    }

    private var filteredWindows: [MockWindow] {
        if searchText.isEmpty { return mockWindows }
        let query = searchText.lowercased()
        return mockWindows.filter {
            $0.title.lowercased().contains(query) ||
            $0.bundleID.lowercased().contains(query)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ── Search bar ──────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                TextField("Search windows…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VoltPaper.foreground.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
                    )
            )

            // ── Fields ──────────────────────────────────────────────
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Window Title")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    TextField("e.g. Minecraft", text: $windowTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Bundle ID")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    TextField("com.example.game", text: $bundleID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
            }

            // ── Refresh ─────────────────────────────────────────────
            HStack {
                Spacer()
                Button {
                    // Placeholder — will call SCK
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Refresh")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                }
                .buttonStyle(.plain)
            }

            // ── Window list ─────────────────────────────────────────
            VStack(spacing: 0) {
                if filteredWindows.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "macwindow.badge.plus")
                                .font(.system(size: 24, weight: .ultraLight))
                                .foregroundStyle(SwooshNeonTokens.Accent.cyan.opacity(0.25))
                            Text("No windows found")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    ForEach(filteredWindows) { window in
                        windowRow(window)
                        if window.id != filteredWindows.last?.id {
                            Rectangle()
                                .fill(SwooshNeonTokens.Line.rule)
                                .frame(height: 0.5)
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(VoltPaper.foreground.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
                    )
            )
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Window row
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private func windowRow(_ window: MockWindow) -> some View {
        let isSelected = (windowTitle == window.title && bundleID == window.bundleID)

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                windowTitle = window.title
                bundleID = window.bundleID
            }
        } label: {
            HStack(spacing: 10) {
                // App icon placeholder
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [window.color.opacity(0.6), window.color.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: window.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(VoltPaper.foreground)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? SwooshNeonTokens.Accent.cyan
                                : SwooshNeonTokens.Canvas.text1
                        )
                        .lineLimit(1)
                    Text(window.bundleID)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SwooshNeonTokens.Accent.cyan.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Mock window model
// ═══════════════════════════════════════════════════════════════════

struct MockWindow: Identifiable {
    let id: String
    let title: String
    let bundleID: String
    let icon: String
    let color: Color

    static let placeholders: [MockWindow] = [
        MockWindow(id: "1", title: "Minecraft", bundleID: "com.mojang.minecraftpe",
                   icon: "cube.fill", color: VoltPaper.Chart.c1),
        MockWindow(id: "2", title: "Counter-Strike 2", bundleID: "com.valvesoftware.cs2",
                   icon: "scope", color: VoltPaper.Chart.c2),
        MockWindow(id: "3", title: "Doom Eternal", bundleID: "com.bethesda.dooneternal",
                   icon: "flame.fill", color: VoltPaper.Chart.c3),
        MockWindow(id: "4", title: "Stardew Valley", bundleID: "com.chucklefish.stardewvalley",
                   icon: "leaf.fill", color: VoltPaper.Chart.c4),
        MockWindow(id: "5", title: "Hades II", bundleID: "com.supergiant.hades2",
                   icon: "bolt.fill", color: VoltPaper.Chart.c5),
    ]
}

#endif
