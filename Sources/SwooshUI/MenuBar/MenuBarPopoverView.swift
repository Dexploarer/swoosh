// SwooshUI/MenuBar/MenuBarPopoverView.swift — The main menu bar popover
//
// Renders sections based on the active configuration.
// Each section is a collapsible card. Supports all card styles.

import SwiftUI
import SwooshGenerativeUI
import SwooshSecrets

public struct MenuBarPopoverView: View {
    @Bindable var manager: MenuBarManager
    @Environment(\.swooshTheme) var theme
    @Environment(AgentShellModel.self) private var shell
    @State private var showingCustomizer = false
    @State private var panelStore = PanelLayoutStore()
    @State private var editingPanels = false

    public init(manager: MenuBarManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            headerBar

            Divider().opacity(0.3)

            // ── Panel host (customizable capsules) ──
            PanelHost(
                store: panelStore,
                surface: "tray",
                context: PanelHostContext(shell: shell),
                editing: $editingPanels
            )
            .environment(shell)
            .frame(maxHeight: manager.config.popoverMaxHeight - 60)

            Divider().opacity(0.3)

            // ── Footer ──
            footerBar
        }
        .frame(width: manager.config.popoverWidth)
        .sheet(isPresented: $showingCustomizer) {
            MenuBarCustomizerView(manager: manager)
        }
    }

    // ── Header ──

    private var headerBar: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(theme.accent)
                .font(.system(size: 14, weight: .semibold))

            Text(manager.config.presetName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            if manager.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            }

            Button {
                Task { await manager.refreshCredentials() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(duration: 0.2)) { editingPanels.toggle() }
            } label: {
                Image(systemName: editingPanels ? "checkmark.circle.fill" : "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(editingPanels ? SwooshNeonTokens.Accent.cyan : theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(editingPanels ? "Done editing" : "Edit panels")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // ── Footer ──

    private var footerBar: some View {
        HStack(spacing: 12) {
            if let lastTime = manager.lastDiscoveryTime {
                Text("Updated \(lastTime, style: .relative) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            Text("\(manager.providerStatuses.count) providers")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.accent)

            if !manager.accessibleBrowsers.isEmpty {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textSecondary)
                Text("\(manager.accessibleBrowsers.count) browsers")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Section card
// ═══════════════════════════════════════════════════════════════════

struct MenuBarSectionCard: View {
    let config: MenuBarSectionConfig
    @Bindable var manager: MenuBarManager
    let cardStyle: MenuBarConfiguration.CardStyle
    let compact: Bool

    @State private var isExpanded: Bool = true
    @Environment(\.swooshTheme) var theme

    init(config: MenuBarSectionConfig, manager: MenuBarManager,
         cardStyle: MenuBarConfiguration.CardStyle, compact: Bool) {
        self.config = config
        self.manager = manager
        self.cardStyle = cardStyle
        self.compact = compact
        self._isExpanded = State(initialValue: !config.collapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            // Section header (toggles collapse)
            if manager.config.showSectionHeaders {
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: config.customIcon ?? config.section.defaultIcon)
                            .font(.system(size: compact ? 10 : 12, weight: .medium))
                            .foregroundStyle(theme.accent)
                            .frame(width: 16)

                        Text(config.customTitle ?? config.section.displayName)
                            .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.textPrimary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }

            // Section content
            if isExpanded {
                sectionContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(compact ? 8 : 12)
        .modifier(CardStyleModifier(style: cardStyle, theme: theme))
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch config.section {
        case .providerStatus:
            ProviderStatusSectionView(
                statuses: manager.providerStatuses,
                maxItems: config.maxItems,
                compact: compact
            )
        case .quickActions:
            QuickActionsSectionView(compact: compact)
        case .usageMeters:
            UsageMetersSectionView(
                statuses: manager.providerStatuses,
                compact: compact
            )
        default:
            // Placeholder for sections being built out
            HStack {
                Text(config.section.displayName)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Not enabled")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Card style modifier
// ═══════════════════════════════════════════════════════════════════

struct CardStyleModifier: ViewModifier {
    let style: MenuBarConfiguration.CardStyle
    let theme: SwooshTheme

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .flat:
            content
                .background(theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .bordered:
            content
                .background(theme.surface.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.textSecondary.opacity(0.15), lineWidth: 0.5)
                )
        case .minimal:
            content
        }
    }
}
