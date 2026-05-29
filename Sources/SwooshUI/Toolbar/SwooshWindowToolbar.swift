// SwooshUI/Toolbar/SwooshWindowToolbar.swift
// SwiftUI toolbar modifier for the main window.
// Reads from SwooshToolbarManager and renders items in user-configured order.

import SwiftUI
import SwooshGenerativeUI

// MARK: - Main toolbar modifier

public struct SwooshWindowToolbar: ViewModifier {
    @State var manager: SwooshToolbarManager
    @State private var showCustomizer = false

    // Badge bindings injected from the app
    public var pendingApprovals: Int
    public var runningAgents: Int
    public var boardCards: Int

    public init(manager: SwooshToolbarManager,
                pendingApprovals: Int = 0,
                runningAgents: Int = 0,
                boardCards: Int = 0) {
        self.manager = manager
        self.pendingApprovals = pendingApprovals
        self.runningAgents = runningAgents
        self.boardCards = boardCards
    }

    public func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    navigationItems
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    primaryItems
                }
            }
            .sheet(isPresented: $showCustomizer) {
                SwooshToolbarCustomizerView(manager: manager)
            }
            .onAppear {
                manager.setBadge(pendingApprovals, for: .approvals)
                manager.setBadge(runningAgents, for: .agentStatus)
                manager.setBadge(boardCards, for: .board)
            }
            .onChange(of: pendingApprovals) { manager.setBadge($1, for: .approvals) }
            .onChange(of: runningAgents)    { manager.setBadge($1, for: .agentStatus) }
            .onChange(of: boardCards)       { manager.setBadge($1, for: .board) }
    }

    // MARK: - Item groups

    @ViewBuilder
    private var navigationItems: some View {
        ForEach(manager.config.items.filter { $0.isVisible && isNavigationItem($0.item) }) { cfg in
            toolbarButton(for: cfg)
        }
    }

    @ViewBuilder
    private var primaryItems: some View {
        ForEach(manager.config.items.filter { $0.isVisible && !isNavigationItem($0.item) }) { cfg in
            if cfg.item == .spacer {
                Spacer()
            } else if cfg.item == .divider {
                Divider()
            } else {
                toolbarButton(for: cfg)
            }
        }
        // Always-present customize button
        Button { showCustomizer = true } label: {
            Image(systemName: "slider.horizontal.3")
                .symbolRenderingMode(.hierarchical)
        }
        .help("Customize Toolbar…")
    }

    private func isNavigationItem(_ item: SwooshToolbarItem) -> Bool {
        [.newChat, .runWorkflow, .board].contains(item)
    }

    @ViewBuilder
    private func toolbarButton(for cfg: ToolbarItemConfig) -> some View {
        let badge = manager.badgeCounts[cfg.item]
        let size = manager.config.iconSize

        Button(action: { handleTap(cfg.item) }) {
            switch cfg.labelStyle {
            case .iconOnly:
                Image(systemName: cfg.item.icon)
                    .font(.system(size: size * 0.7, weight: .semibold))
                    .foregroundStyle(cfg.item.accentColor)
                    .overlay(alignment: .topTrailing) {
                        if let b = badge, b > 0, manager.config.showBadges {
                            BadgeView(count: b)
                        }
                    }

            case .labelOnly:
                Text(cfg.effectiveLabel)
                    .font(.system(size: 12, weight: .medium))

            case .iconAndLabel:
                Label {
                    Text(cfg.effectiveLabel)
                        .font(.system(size: 11, weight: .medium))
                } icon: {
                    Image(systemName: cfg.item.icon)
                        .font(.system(size: size * 0.6, weight: .semibold))
                        .foregroundStyle(cfg.item.accentColor)
                }
                .overlay(alignment: .topTrailing) {
                    if let b = badge, b > 0, manager.config.showBadges {
                        BadgeView(count: b)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .help(cfg.effectiveLabel)
    }

    private func handleTap(_ item: SwooshToolbarItem) {
        // Actions wired in the app layer via environment / notifications
        NotificationCenter.default.post(name: .swooshToolbarAction, object: item.rawValue)
    }
}

// MARK: - Badge view

private struct BadgeView: View {
    let count: Int
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(VoltPaper.foreground)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(Capsule().fill(VoltPaper.destructive))
            .offset(x: 6, y: -4)
    }
}

// MARK: - Toolbar action notification

public extension Notification.Name {
    static let swooshToolbarAction = Notification.Name("swoosh.toolbar.action")
}

// MARK: - View extension

public extension View {
    func swooshToolbar(
        manager: SwooshToolbarManager,
        pendingApprovals: Int = 0,
        runningAgents: Int = 0,
        boardCards: Int = 0
    ) -> some View {
        modifier(SwooshWindowToolbar(
            manager: manager,
            pendingApprovals: pendingApprovals,
            runningAgents: runningAgents,
            boardCards: boardCards
        ))
    }
}
