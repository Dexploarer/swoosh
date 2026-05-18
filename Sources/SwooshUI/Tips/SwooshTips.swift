// SwooshUI/Tips/SwooshTips.swift — Onboarding hints via TipKit (0.4A)
//
// Lightweight `Tip` definitions that surface on first-touch interactions
// inside the dashboard. Each tip auto-dismisses once the user has performed
// the underlying action — TipKit tracks displayedCount itself.
//
// Apple guidance: tips should teach a single discoverable feature, never
// nag, and disappear after the user has tried what they teach. We use
// `EventRule` so the tip clears once a registered event fires.

import SwiftUI
#if canImport(TipKit)
import TipKit
#endif

// MARK: - Tip events

#if canImport(TipKit)
@available(macOS 14.0, iOS 17.0, *)
public extension Tips {
    /// Centralised TipKit event names. Each tip subscribes to its trigger
    /// and dismisses once the user fires the corresponding event.
    enum SwooshEvent {
        public static let openedAppearance     = Event(id: "ai.swoosh.openedAppearance")
        public static let approvedToolCall     = Event(id: "ai.swoosh.approvedToolCall")
        public static let setProvider          = Event(id: "ai.swoosh.setProvider")
        public static let customizedMenuBar    = Event(id: "ai.swoosh.customizedMenuBar")
        public static let viewedAuditLog       = Event(id: "ai.swoosh.viewedAuditLog")
        public static let pinnedMemory         = Event(id: "ai.swoosh.pinnedMemory")
    }
}
#endif

// MARK: - Tips

#if canImport(TipKit)
@available(macOS 14.0, iOS 17.0, *)
public struct CustomizeAppearanceTip: Tip {
    public init() {}
    public var title: Text {
        Text("Make Swoosh yours")
    }
    public var message: Text? {
        Text("Open **Appearance** to pick a theme or design your own. Colors, glass, motion — everything is live.")
    }
    public var image: Image? {
        Image(systemName: "paintbrush.fill")
    }
    public var actions: [Action] {
        [Action(id: "open", title: "Open Appearance")]
    }
    public var rules: [Rule] {
        [
            #Rule(Tips.SwooshEvent.openedAppearance) { $0.donations.count == 0 },
        ]
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct SetProviderTip: Tip {
    public init() {}
    public var title: Text {
        Text("Connect a model provider")
    }
    public var message: Text? {
        Text("Swoosh auto-discovers keys in your environment. Visit **Providers** to verify or add one.")
    }
    public var image: Image? {
        Image(systemName: "cloud.fill")
    }
    public var rules: [Rule] {
        [
            #Rule(Tips.SwooshEvent.setProvider) { $0.donations.count == 0 },
        ]
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct CustomizeMenuBarTip: Tip {
    public init() {}
    public var title: Text {
        Text("Reshape the menu bar popover")
    }
    public var message: Text? {
        Text("Drag sections to reorder, toggle to hide. Pick a preset or build your own layout.")
    }
    public var image: Image? {
        Image(systemName: "menubar.dock.rectangle")
    }
    public var rules: [Rule] {
        [
            #Rule(Tips.SwooshEvent.customizedMenuBar) { $0.donations.count == 0 },
        ]
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct ApprovalCenterTip: Tip {
    public init() {}
    public var title: Text {
        Text("You're always in the loop")
    }
    public var message: Text? {
        Text("Risky tool calls pause for your approval. Tap the badge to review what an agent wants to do.")
    }
    public var image: Image? {
        Image(systemName: "hand.raised.fill")
    }
    public var rules: [Rule] {
        [
            #Rule(Tips.SwooshEvent.approvedToolCall) { $0.donations.count == 0 },
        ]
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct WhyAuditTip: Tip {
    public init() {}
    public var title: Text {
        Text("Why did the agent do that?")
    }
    public var message: Text? {
        Text("Every response records the memories, setup report, and tools it used. Run `/why` or open the **Audit Log**.")
    }
    public var image: Image? {
        Image(systemName: "list.bullet.rectangle.fill")
    }
    public var rules: [Rule] {
        [
            #Rule(Tips.SwooshEvent.viewedAuditLog) { $0.donations.count == 0 },
        ]
    }
}
#endif

// MARK: - Configuration helper

public enum SwooshTipsConfigurator {
    /// Configure TipKit once on app launch. Pass the same data store URL
    /// every session so display counts persist. Safe to call multiple times.
    @MainActor
    public static func configure() {
        #if canImport(TipKit)
        if #available(macOS 14.0, iOS 17.0, *) {
            do {
                try Tips.configure([
                    .displayFrequency(.daily),
                    .datastoreLocation(.applicationDefault),
                ])
            } catch {
                print("[SwooshUI/Tips] Failed to configure TipKit: \(error)")
            }
        }
        #endif
    }
}

// MARK: - View extension

#if canImport(TipKit)
@available(macOS 14.0, iOS 17.0, *)
public extension View {
    /// Convenience wrapper around `.popoverTip` so call sites don't import
    /// TipKit directly.
    @ViewBuilder
    func swooshTip<T: Tip>(_ tip: T) -> some View {
        self.popoverTip(tip)
    }
}
#endif
