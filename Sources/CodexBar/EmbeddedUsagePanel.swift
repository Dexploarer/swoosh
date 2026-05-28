// CodexBar/EmbeddedUsagePanel.swift — Embeddable usage panel
//
// Wraps CodexBar's internal UsageStore + SettingsStore into a SwiftUI
// view showing all enabled AI provider usage with bars and status.

import CodexBarCore
import SwiftUI

/// Self-contained usage panel showing all enabled AI provider usage.
struct EmbeddedUsagePanel: View {
    let store: UsageStore
    let settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Label("AI Usage", systemImage: "chart.bar.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task { await store.refresh(forceTokenUsage: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.64))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
                    .opacity(0.08)
                    .padding(.horizontal, 12)

                // Provider cards
                let providers = store.enabledProviders()
                if providers.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(providers, id: \.self) { provider in
                            providerRow(provider)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .background(Color.black)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28))
                .foregroundStyle(Color.white.opacity(0.40))
            Text("No providers configured")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.64))
            Text("Enable providers in Settings\nto see usage here.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.40))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func providerRow(_ provider: UsageProvider) -> some View {
        let snapshot = store.snapshot(for: provider)
        let metadata = store.metadata(for: provider)
        let error = store.errors[provider]
        let isRefreshing = store.refreshingProviders.contains(provider)

        VStack(alignment: .leading, spacing: 6) {
            // Provider header
            HStack(alignment: .firstTextBaseline) {
                Text(metadata.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                } else if let identity = snapshot?.identity {
                    Text(identity.accountEmail ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Usage bars from snapshot
            if let snapshot = snapshot {
                if let primary = snapshot.primary {
                    usageBar(
                        title: metadata.sessionLabel,
                        percent: primary.remainingPercent,
                        resetText: UsageFormatter.resetLine(for: primary, style: .countdown, now: Date())
                    )
                }
                if let secondary = snapshot.secondary {
                    usageBar(
                        title: metadata.weeklyLabel,
                        percent: secondary.remainingPercent,
                        resetText: UsageFormatter.resetLine(for: secondary, style: .countdown, now: Date())
                    )
                }
            } else if let error = error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(2)
            } else {
                Text("Loading…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Status indicator
            if let status = store.statuses[provider] {
                HStack(spacing: 4) {
                    Circle()
                        .fill(indicatorColor(status.indicator))
                        .frame(width: 6, height: 6)
                    if let desc = status.description {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var neonCyan: Color {
        Color(red: 0x26 / 255.0, green: 0xE0 / 255.0, blue: 0xE8 / 255.0)
    }
    private var neonGreen: Color {
        Color(red: 0x3C / 255.0, green: 0xDF / 255.0, blue: 0x52 / 255.0)
    }
    private var neonGold: Color {
        Color(red: 0xF2 / 255.0, green: 0xB5 / 255.0, blue: 0x30 / 255.0)
    }
    private var neonError: Color {
        Color(red: 0xFF / 255.0, green: 0x52 / 255.0, blue: 0x52 / 255.0)
    }

    @ViewBuilder
    private func usageBar(title: String, percent: Double, resetText: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.64))
                Spacer()
                Text(String(format: "%.0f%% left", percent))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(percent < 20 ? neonError : Color.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(percent))
                        .frame(width: geo.size.width * min(1, max(0, percent / 100)))
                }
            }
            .frame(height: 6)
            if let resetText = resetText {
                Text(resetText)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.40))
            }
        }
    }

    private func barColor(_ percent: Double) -> Color {
        if percent < 10 { return neonError }
        if percent < 25 { return neonGold }
        return neonCyan
    }

    private func indicatorColor(_ indicator: ProviderStatusIndicator) -> Color {
        switch indicator {
        case .none: return neonGreen
        case .minor: return neonGold
        case .major, .critical: return neonError
        case .maintenance: return neonGold
        case .unknown: return .gray
        }
    }
}
