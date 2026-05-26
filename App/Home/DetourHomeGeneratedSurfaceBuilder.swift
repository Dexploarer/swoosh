// DetourHomeGeneratedSurfaceBuilder.swift — deterministic home surface projection (0.5A)

import Foundation

@MainActor
enum DetourHomeGeneratedSurfaceBuilder {
    static func build(
        store: OnboardingStore,
        focus: DetourHomeFocus,
        sections: [DetourSetupInsightSection],
        summary: DetourSetupCapabilitySummary,
        command: String,
        wallet: DetourHomeWalletModel,
        inbox: DetourHomeInboxModel
    ) -> DetourGeneratedSurface {
        var components: [DetourGeneratedComponent] = []
        let children = rootChildren(for: focus)
        add(&components, "root", .column(children: children, spacing: 14))
        intent(&components, store: store, focus: focus, summary: summary, command: command)
        setup(&components, sections: sections, focus: focus)
        add(&components, "apps.full", .nativePanel(.apps))
        social(&components, sections: sections)
        inboxSurface(&components, inbox: inbox)
        walletSurface(&components, wallet: wallet)
        add(&components, "settings.full", .nativePanel(.settings))
        return DetourGeneratedSurface(rootID: "root", components: components)
    }

    private static func rootChildren(for focus: DetourHomeFocus) -> [String] {
        switch focus {
        case .overview:
            return ["intent", "capabilities", "social.compact", "inbox.compact"]
        case .apps:
            return ["intent", "apps.full"]
        case .social:
            return ["intent", "social.full"]
        case .inbox:
            return ["intent", "inbox.full"]
        case .wallet:
            return ["intent", "wallet.full"]
        case .setup:
            return ["intent", "setup.full"]
        case .settings:
            return ["intent", "settings.full"]
        }
    }

    private static func intent(
        _ components: inout [DetourGeneratedComponent],
        store: OnboardingStore,
        focus: DetourHomeFocus,
        summary: DetourSetupCapabilitySummary,
        command: String
    ) {
        let user = store.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = user.isEmpty ? "Personal workspace" : "\(user)'s workspace"
        let prompt = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = prompt.isEmpty ? focusDetail(focus, summary: summary) : "Showing the surface for: \(prompt)"
        add(&components, "intent", .panel(child: "intent.body", tone: .secondary))
        add(&components, "intent.body", .hero(
            agentName: focus.title,
            summary: detail,
            workspace: workspace
        ))
        let chips = capabilityChips(summary: summary)
        add(&components, "capabilities", .chips(
            title: "What Detour can use right now",
            subtitle: "This is generated from live setup state, not a static menu.",
            chips: Array(chips.prefix(8)),
            overflow: max(chips.count - 8, 0)
        ))
    }

    private static func setup(
        _ components: inout [DetourGeneratedComponent],
        sections: [DetourSetupInsightSection],
        focus: DetourHomeFocus
    ) {
        let items = setupItems(sections: sections, focus: focus)
        add(&components, "setup.full", .panel(child: "setup.body", tone: .secondary))
        add(&components, "setup.title", .heading(
            title: "Setup Detour can act on",
            subtitle: "Only selected, visible, non-removed items are shown here."
        ))
        if items.isEmpty {
            add(&components, "setup.items", .message(
                title: "Nothing needs setup here.",
                detail: "Run a scan or review setup to add connectors, accounts, permissions, and providers.",
                tone: .secondary
            ))
        } else {
            let ids = items.prefix(10).map { item in
                let id = "setup.\(DetourSetupInsightRedaction.stableIDComponent(item.id))"
                add(&components, id, .setupItem(item))
                return id
            }
            add(&components, "setup.items", .column(children: Array(ids), spacing: 10))
        }
        add(&components, "setup.body", .column(children: ["setup.title", "setup.items"], spacing: 12))
    }

    private static func social(_ components: inout [DetourGeneratedComponent], sections: [DetourSetupInsightSection]) {
        let items = socialItems(sections)
        let chips = items.prefix(8).map {
            DetourGeneratedChip(id: $0.id, title: $0.title, tone: tone(for: $0.status))
        }
        add(&components, "social.compact", .chips(
            title: "Social surface",
            subtitle: items.isEmpty ? "Connect Discord, Telegram, X, iMessage, or AgentMail." : "\(items.count) social and relationship items ready for routing.",
            chips: Array(chips),
            overflow: max(items.count - chips.count, 0)
        ))
        add(&components, "social.full", .nativePanel(.socialOnChain))
    }

    private static func inboxSurface(_ components: inout [DetourGeneratedComponent], inbox: DetourHomeInboxModel) {
        let detail = inbox.pendingCount > 0 ? "\(inbox.pendingCount) pending approvals." : inbox.state.label
        add(&components, "inbox.compact", .message(
            title: "Universal inbox",
            detail: "\(inbox.items.count) recent items. \(detail)",
            tone: inbox.pendingCount > 0 ? .orange : .blue
        ))
        add(&components, "inbox.full", .nativePanel(.universalInbox))
    }

    private static func walletSurface(_ components: inout [DetourGeneratedComponent], wallet: DetourHomeWalletModel) {
        add(&components, "wallet.full", .nativePanel(.socialOnChain))
    }

    private static func setupItems(
        sections: [DetourSetupInsightSection],
        focus: DetourHomeFocus
    ) -> [DetourSetupInsightItem] {
        let all = sections.flatMap(\.items)
        guard focus != .setup else { return all }
        return all.filter { $0.status.needsAttention }.isEmpty ? Array(all.prefix(6)) : all.filter { $0.status.needsAttention }
    }

    private static func socialItems(_ sections: [DetourSetupInsightSection]) -> [DetourSetupInsightItem] {
        let needles = ["discord", "telegram", "imessage", "messages", "x account", "x session", "agentmail", "relationship"]
        var seen: Set<String> = []
        return sections.flatMap(\.items).filter { item in
            let value = [item.id, item.title, item.subtitle ?? "", item.detail, item.sourceLabel ?? ""]
                .joined(separator: " ")
                .lowercased()
            return needles.contains { value.contains($0) }
        }
        .filter { seen.insert($0.id).inserted }
    }

    private static func capabilityChips(summary: DetourSetupCapabilitySummary) -> [DetourGeneratedChip] {
        [
            DetourGeneratedChip(id: "using", title: "\(summary.using) selected", tone: .green),
            DetourGeneratedChip(id: "verified", title: "\(summary.verified) verified", tone: .blue),
            DetourGeneratedChip(id: "pending", title: "\(summary.pending) pending", tone: .secondary),
            DetourGeneratedChip(id: "attention", title: "\(summary.needsAttention) need attention", tone: summary.needsAttention > 0 ? .orange : .green),
        ]
    }

    private static func focusDetail(_ focus: DetourHomeFocus, summary: DetourSetupCapabilitySummary) -> String {
        switch focus {
        case .overview:
            return summary.needsAttention == 0 ? "Ready to work from the menu bar or a canvas." : "\(summary.needsAttention) setup items still need attention."
        case .apps:
            return "Browse every supported app, then connect and test only what you choose."
        case .social:
            return "Route Discord, Telegram, X, iMessage, AgentMail, and relationship context."
        case .inbox:
            return "Messages, replies, approvals, and agent activity stay in one place."
        case .wallet:
            return "Wallets, Solana, BNB Chain, EVM, Hyperliquid, and social context."
        case .setup:
            return "Review the accounts, credentials, connectors, permissions, and providers Detour can use."
        case .settings:
            return "Configure Detour, runtime access, setup permissions, connectors, and canvas behavior without rerunning onboarding."
        }
    }

    private static func tone(for status: DetourSetupInsightStatus) -> DetourGeneratedTone {
        status.needsAttention ? .orange : .green
    }

    private static func add(
        _ components: inout [DetourGeneratedComponent],
        _ id: String,
        _ body: DetourGeneratedComponentBody
    ) {
        components.append(DetourGeneratedComponent(id: id, body: body))
    }
}
