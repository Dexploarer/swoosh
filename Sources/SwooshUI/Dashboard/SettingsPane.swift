// SwooshUI/Dashboard/SettingsPane.swift — Settings page in the dashboard — 0.9Y
//
// Appearance, daemon connection (read-only, live from the daemon),
// personalisation, and about. Provider/model setup lives in the Models tab
// (ProvidersPane) — it is NOT duplicated here. The old @AppStorage provider
// block was dead config (keys written to UserDefaults that nothing read);
// it was removed rather than relocated.

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct SettingsPane: View {
    @AppStorage("swoosh.appearance.theme") private var themeName: String = "midnight"
    @AppStorage("swoosh.appearance.accentColor") private var accentName: String = "cyan"
    @AppStorage("swoosh.scout.personalisation") private var personalisationDepth: String = "standard"

    @State private var connection: RuntimeConfigResponse?
    @State private var versionString: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    .padding(.bottom, 28)

                // ── Appearance ───────────────────────────────
                sectionHeader("Appearance")
                cardGroup {
                    settingRow(icon: "paintpalette", title: "Theme") {
                        Picker("", selection: $themeName) {
                            Text("Midnight").tag("midnight")
                            Text("Charcoal").tag("charcoal")
                            Text("OLED Black").tag("oled")
                            Text("Light").tag("light")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    cardDivider
                    settingRow(icon: "circle.fill", title: "Accent colour") {
                        Picker("", selection: $accentName) {
                            Text("Violet").tag("cyan")
                            Text("Lime").tag("green")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }

                // ── Daemon (read-only, live) ─────────────────
                sectionHeader("Daemon")
                    .padding(.top, 24)
                cardGroup {
                    settingRow(icon: "network", title: "Connection") {
                        Text(connectionText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    }
                    cardDivider
                    settingRow(icon: "bolt.horizontal.circle", title: "Status") {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(connection != nil ? VoltPaper.accent : VoltPaper.destructive)
                                .frame(width: 7, height: 7)
                            Text(connection != nil ? "Running (in-process)" : "Unreachable")
                                .font(.system(size: 12))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                        }
                    }
                }

                // ── Personalisation ─────────────────────────
                sectionHeader("Personalisation")
                    .padding(.top, 24)
                cardGroup {
                    settingRow(icon: "person.and.background.dotted", title: "Scout depth") {
                        Picker("", selection: $personalisationDepth) {
                            Text("Minimal").tag("minimal")
                            Text("Standard").tag("standard")
                            Text("Deep").tag("deep")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }

                // ── Providers (managed elsewhere) ────────────
                sectionHeader("Providers & Models")
                    .padding(.top, 24)
                cardGroup {
                    HStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage providers in the Models tab")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                            Text("API keys, OAuth, and the active model are configured there and saved to the daemon + Keychain.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                // ── Agent & Safety (pointer) ─────────────────
                cardGroup {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(VoltPaper.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Permissions & safety in the Safety tab")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                            Text("Permission preset, the enforced safety flags, Firewall grants, and the Approvals queue live under Agent.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .padding(.top, 8)

                // ── About ───────────────────────────────────
                sectionHeader("About")
                    .padding(.top, 24)
                cardGroup {
                    HStack(spacing: 12) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Detour Agent")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                            Text(versionText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                Spacer(minLength: 40)
            }
            .padding(32)
            .frame(maxWidth: 640, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await loadConnection() }
    }

    private var connectionText: String {
        guard let connection else { return "—" }
        let host = connection.daemonHost ?? "127.0.0.1"
        let port = connection.daemonPort.map(String.init) ?? "8787"
        return "\(host):\(port)"
    }

    private var versionText: String {
        let v = versionString ?? "—"
        return "\(v) · macOS 26 · Swift 6.3"
    }

    private func loadConnection() async {
        guard let client = SwooshDaemonClient.client() else { return }
        connection = try? await client.runtimeConfig()
        versionString = try? await client.version().version
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private func cardGroup(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SwooshNeonTokens.Canvas.text1.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
                )
        )
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(SwooshNeonTokens.Line.rule)
            .frame(height: 0.5)
            .padding(.leading, 44)
    }

    @ViewBuilder
    private func settingRow(icon: String, title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

#endif
