// SwooshWidgets/SwooshMenuBarController.swift
// Native macOS menu bar integration — inspired by CryptoBar's lightweight
// NSStatusItem approach (https://github.com/Cmalf-Labs/CryptoBar).
//
// Shows: agent status, pending approvals, and top token price.
// Clicking the menu bar item opens the full TUI or approval queue.

import Foundation
#if canImport(AppKit)
import AppKit

@MainActor
public final class SwooshMenuBarController: NSObject {

    // MARK: - State

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var refreshTimer: Timer?

    private var snapshot: SwooshWidgetSnapshot?
    private var portfolio: CryptoPortfolioSnapshot?

    public var onShowTUI: (() -> Void)?
    public var onShowApprovals: (() -> Void)?
    public var onQuit: (() -> Void)?

    // MARK: - Lifecycle

    public override init() { super.init() }

    public func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(menuBarClicked)
        statusItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        buildMenu()
        refresh()
        startRefreshTimer()
    }

    public func uninstall() {
        refreshTimer?.invalidate()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    // MARK: - Timer

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    // MARK: - Data refresh

    private func refresh() {
        snapshot = SwooshWidgetSnapshot.load()
        portfolio = CryptoPortfolioSnapshot.load()
        updateButton()
        buildMenu()
    }

    // MARK: - Button title

    private func updateButton() {
        guard let button = statusItem?.button else { return }

        let icon = systemStatusIcon()
        var title = icon

        // Pending approvals badge
        if let pending = snapshot?.pendingApprovals, pending > 0 {
            title += " ⚡\(pending)"
        }

        // Top token price (CryptoBar style)
        if let top = portfolio?.entries.first, let price = top.price {
            title += "  \(top.symbol) \(price.priceLabel)"
            let changeColor: NSColor = price.isPositive ? .systemGreen : .systemRed
            let attr = NSMutableAttributedString(string: title)
            let range = NSRange(title.range(of: price.changeLabel)!, in: title)
            attr.addAttribute(.foregroundColor, value: changeColor, range: range)
            button.attributedTitle = attr
            return
        }

        button.title = title
    }

    private func systemStatusIcon() -> String {
        switch snapshot?.systemStatus {
        case .healthy: return "⚡"
        case .degraded: return "⚠️"
        case .offline: return "🔴"
        case nil: return "◉"
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let m = NSMenu()
        m.autoenablesItems = false

        // Header
        let header = NSMenuItem(title: "Swoosh Agent", action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)
        m.addItem(.separator())

        // Status row
        if let snap = snapshot {
            let statusItem = NSMenuItem(title: statusSummary(snap), action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            m.addItem(statusItem)
            m.addItem(.separator())

            // Pending approvals
            if snap.pendingApprovals > 0 {
                let appItem = NSMenuItem(
                    title: "⚡ \(snap.pendingApprovals) Pending Approval\(snap.pendingApprovals == 1 ? "" : "s")",
                    action: #selector(showApprovals),
                    keyEquivalent: ""
                )
                appItem.target = self
                m.addItem(appItem)
                m.addItem(.separator())
            }
        }

        // Portfolio section
        if let portfolio = portfolio, !portfolio.entries.isEmpty {
            let portfolioHeader = NSMenuItem(title: "Portfolio · \(portfolio.totalValueLabel)", action: nil, keyEquivalent: "")
            portfolioHeader.isEnabled = false
            m.addItem(portfolioHeader)

            for entry in portfolio.entries.prefix(5) {
                let change = entry.price?.changeLabel ?? "--"
                let title = "\(entry.symbol)  \(entry.price?.priceLabel ?? "--")  \(change)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                m.addItem(item)
            }
            m.addItem(.separator())
        }

        // Actions
        let openItem = NSMenuItem(title: "Open Swoosh", action: #selector(openTUI), keyEquivalent: "")
        openItem.target = self
        m.addItem(openItem)

        m.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Swoosh", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        m.addItem(quitItem)

        menu = m
    }

    private func statusSummary(_ snap: SwooshWidgetSnapshot) -> String {
        var parts: [String] = []
        if snap.activeAgents > 0 { parts.append("\(snap.activeAgents) agent\(snap.activeAgents == 1 ? "" : "s")") }
        if snap.activeWorkflows > 0 { parts.append("\(snap.activeWorkflows) workflow\(snap.activeWorkflows == 1 ? "" : "s")") }
        if parts.isEmpty { parts.append("idle") }
        if let cost = snap.totalCost { parts.append(cost) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    @objc private func menuBarClicked() {
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openTUI() { onShowTUI?() }
    @objc private func showApprovals() { onShowApprovals?() }
    @objc private func quitApp() { onQuit?() }
}

#endif
