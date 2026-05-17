// SwooshUI/MenuBar/ProviderStatusPane.swift — Providers tab in the main dashboard
//
// Shows all discovered provider credentials with their sources,
// health status, and browser accessibility.

import SwiftUI
import SwooshSecrets

struct ProviderStatusPane: View {
    @State private var manager = MenuBarManager()
    @State private var hasLoaded = false
    @Environment(\.swooshTheme) var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ── Header ──
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Provider Credentials")
                            .font(.largeTitle.bold())
                        Text("Discovered from environment, config files, and Keychain")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { await manager.refreshCredentials() }
                    } label: {
                        Label(
                            manager.isRefreshing ? "Scanning…" : "Scan",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.isRefreshing)
                }

                // ── Browser access ──
                if !manager.accessibleBrowsers.isEmpty {
                    GroupBox {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .foregroundStyle(theme.info)
                            Text("Cookie decryption available for:")
                                .font(.system(size: 13))
                            ForEach(manager.accessibleBrowsers, id: \.self) { browser in
                                Text(browser)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(theme.info.opacity(0.12), in: Capsule())
                            }
                            Spacer()
                        }
                    }
                }

                // ── Provider grid ──
                if manager.providerStatuses.isEmpty && !manager.isRefreshing {
                    ContentUnavailableView {
                        Label("No Providers Found", systemImage: "cloud.slash")
                    } description: {
                        Text("Set API keys in environment variables, config files, or Keychain.")
                    }
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ], spacing: 12) {
                        ForEach(manager.providerStatuses) { status in
                            ProviderCard(status: status)
                        }
                    }
                }

                // ── Discovery sources legend ──
                GroupBox("Discovery Sources") {
                    VStack(alignment: .leading, spacing: 6) {
                        legendRow("ENV", "Environment variables (OPENAI_API_KEY, etc.)", "terminal.fill")
                        legendRow("FILE", "Config files (~/.codex/, ~/.claude/, etc.)", "doc.fill")
                        legendRow("KEY", "Keychain items (Claude Code, Copilot, Gemini CLI)", "key.fill")
                        legendRow("COOKIE", "Browser cookies (Chrome, Brave, Edge Safe Storage)", "globe")
                    }
                }
            }
            .padding(32)
        }
        .navigationTitle("Providers")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await manager.refreshCredentials()
        }
    }

    private func legendRow(_ badge: String, _ description: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Text(badge)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.accent)
                .frame(width: 50, alignment: .leading)

            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 16)

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider card
// ═══════════════════════════════════════════════════════════════════

struct ProviderCard: View {
    let status: ProviderCredentialStatus

    @Environment(\.swooshTheme) var theme
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(status.isHealthy ? theme.success : theme.error)
                    .frame(width: 8, height: 8)

                Text(status.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Image(systemName: kindIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }

            HStack {
                Text(sourceBadge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor, in: Capsule())

                Spacer()

                if let lastChecked = status.lastChecked {
                    Text(lastChecked, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isHovered ? theme.accent.opacity(0.3) : theme.textSecondary.opacity(0.1),
                    lineWidth: isHovered ? 1.5 : 0.5
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var sourceBadge: String {
        switch status.source {
        case .environment:        return "ENV"
        case .configFile:         return "FILE"
        case .keychainThirdParty: return "KEY"
        case .browserCookie:      return "COOKIE"
        case .swooshKeychain:     return "SWOOSH"
        }
    }

    private var badgeColor: Color {
        switch status.source {
        case .environment:        return theme.info
        case .configFile:         return theme.warning
        case .keychainThirdParty: return theme.secondaryAccent
        case .browserCookie:      return theme.success
        case .swooshKeychain:     return theme.accent
        }
    }

    private var kindIcon: String {
        switch status.credentialKind {
        case .apiKey:        return "key.fill"
        case .oauthToken:    return "person.badge.key.fill"
        case .sessionCookie: return "globe"
        case .bearerToken:   return "shield.fill"
        }
    }
}
