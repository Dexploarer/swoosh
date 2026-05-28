// CodexBar/TrayTabView.swift — Two-panel tray dropdown
//
// The menu-bar popover has two modes:
//   • Chat   — provided by the host via @ViewBuilder
//   • Usage  — CodexBar's embedded provider usage panel
//
// Lives in the CodexBar module so it has access to internal
// UsageStore/SettingsStore types. The chat content is injected
// via a generic view builder to avoid circular deps.

import AppKit
import CodexBarCore
import SwiftUI

/// Two-panel tray: Chat and Usage tabs.
/// `ChatContent` is the host-supplied chat view (e.g. AgentShellView).
public struct TrayTabView<ChatContent: View>: View {
    let chatContent: ChatContent
    let store: UsageStore
    let settings: SettingsStore

    public enum Tab: String, CaseIterable {
        case chat = "Chat"
        case usage = "Usage"

        var icon: String {
            switch self {
            case .chat: return "bubble.left.fill"
            case .usage: return "chart.bar.fill"
            }
        }
    }

    @State private var selectedTab: Tab = .chat

    /// Create a two-panel tray. Call from the host app, passing in CodexBar
    /// stores that were created at app launch.
    ///
    /// Because `UsageStore` and `SettingsStore` are internal to CodexBar,
    /// callers must use the `makeTrayTabView` factory instead.
    init(
        store: UsageStore,
        settings: SettingsStore,
        @ViewBuilder chat: () -> ChatContent
    ) {
        self.store = store
        self.settings = settings
        self.chatContent = chat()
    }

    private var neonCyan: Color {
        Color(red: 0x26 / 255.0, green: 0xE0 / 255.0, blue: 0xE8 / 255.0)
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBar

            Divider()
                .opacity(0.08)

            // Content
            Group {
                switch selectedTab {
                case .chat:
                    chatContent
                case .usage:
                    EmbeddedUsagePanel(store: store, settings: settings)
                        .environment(\.colorScheme, .dark)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
            Spacer()
            settingsButton
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var settingsButton: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.40))
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(
                isSelected ? neonCyan : Color.white.opacity(0.40)
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? neonCyan.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? neonCyan.opacity(0.3) : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Factory Helpers

final class AlwaysHiddenStatusItem: NSStatusItem {
    override var isVisible: Bool {
        get { false }
        set { super.isVisible = false }
    }
}

final class SilentStatusBar: NSStatusBar {
    override func statusItem(withLength length: CGFloat) -> NSStatusItem {
        let item = super.statusItem(withLength: length)
        object_setClass(item, AlwaysHiddenStatusItem.self)
        item.isVisible = false
        return item
    }
}

// MARK: - Factory

/// Public factory so the host app can create a `TrayTabView` without
/// directly touching internal CodexBar stores. The host calls this at
/// app-init time.
public struct CodexBarHost {
    public let _store: AnyObject      // UsageStore
    public let _settings: AnyObject   // SettingsStore
    public let _selection: AnyObject   // PreferencesSelection
    public let _managedCodexAccountCoordinator: AnyObject // ManagedCodexAccountCoordinator
    public let _codexAccountPromotionCoordinator: AnyObject? // CodexAccountPromotionCoordinator?
    public let _statusController: AnyObject // StatusItemControlling

    /// Bootstrap CodexBar and return an opaque host handle.
    @MainActor
    public static func bootstrap() -> CodexBarHost {
        CodexBarLog.bootstrapIfNeeded(.init(
            destination: .oslog(subsystem: "ai.detour.codexbar"),
            level: .verbose,
            json: false))
        
        let settings = SettingsStore()
        let language = settings.appLanguage
        if language.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        }
        configureUsageFormatterLocalizationProvider()

        let selection = PreferencesSelection()
        let managedCodexAccountCoordinator = ManagedCodexAccountCoordinator()
        managedCodexAccountCoordinator.onManagedAccountsDidChange = {
            _ = settings.persistResolvedCodexActiveSourceCorrectionIfNeeded()
        }
        _ = settings.persistResolvedCodexActiveSourceCorrectionIfNeeded()

        let fetcher = UsageFetcher()
        let browserDetection = BrowserDetection(cacheTTL: BrowserDetection.defaultCacheTTL)
        let account = fetcher.loadAccountInfo()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: browserDetection,
            settings: settings
        )

        let codexAccountPromotionCoordinator = CodexAccountPromotionCoordinator(
            settingsStore: settings,
            usageStore: store,
            managedAccountCoordinator: managedCodexAccountCoordinator
        )

        let silentStatusBar = SilentStatusBar()
        let statusController = StatusItemController(
            store: store,
            settings: settings,
            account: account,
            updater: DisabledUpdaterController(),
            preferencesSelection: selection,
            managedCodexAccountCoordinator: managedCodexAccountCoordinator,
            codexAccountPromotionCoordinator: codexAccountPromotionCoordinator,
            statusBar: silentStatusBar
        )

        return CodexBarHost(
            _store: store,
            _settings: settings,
            _selection: selection,
            _managedCodexAccountCoordinator: managedCodexAccountCoordinator,
            _codexAccountPromotionCoordinator: codexAccountPromotionCoordinator,
            _statusController: statusController
        )
    }

    /// Build the two-panel tray view. Chat content is injected via closure.
    @MainActor
    public func makeTrayTabView<C: View>(
        @ViewBuilder chat: () -> C
    ) -> TrayTabView<C> {
        TrayTabView(
            store: _store as! UsageStore,
            settings: _settings as! SettingsStore,
            chat: chat
        )
    }

    /// Build the preferences panel/view.
    @MainActor
    public func makePreferencesView() -> some View {
        PreferencesView(
            settings: _settings as! SettingsStore,
            store: _store as! UsageStore,
            updater: DisabledUpdaterController(),
            selection: _selection as! PreferencesSelection,
            managedCodexAccountCoordinator: _managedCodexAccountCoordinator as! ManagedCodexAccountCoordinator,
            codexAccountPromotionCoordinator: _codexAccountPromotionCoordinator as? CodexAccountPromotionCoordinator,
            runProviderLoginFlow: { [statusController = _statusController as? StatusItemController] provider in
                await statusController?.runLoginFlowFromSettings(provider: provider)
            }
        )
    }
}
