// CodexBar/TrayTabView.swift — CodexBar host + factories
//
// Bootstraps CodexBar's usage/settings stores and exposes opaque factories
// the host app uses to embed CodexBar surfaces:
//   • makeUsagePanel()      — the provider quota panel (hosted inside
//                             SwooshUI's MenuBarTray as the "Usage" tab)
//   • makePreferencesView() — the full preferences window
//
// Lives in the CodexBar module so it can reach internal
// UsageStore/SettingsStore types; views are returned opaquely so those
// types stay encapsulated. (The old two-panel TrayTabView was retired when
// SwooshUI.MenuBarTray became the app's tray container.)

import AppKit
import CodexBarCore
import SwiftUI

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

/// Public factory so the host app can create CodexBar surfaces without
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

    /// Build the embedded usage panel (CodexBar's provider quota view) for
    /// hosting inside SwooshUI's `MenuBarTray` as the "Usage" tab. Returns an
    /// opaque view so the internal `UsageStore`/`SettingsStore` stay
    /// encapsulated.
    @MainActor
    public func makeUsagePanel() -> some View {
        EmbeddedUsagePanel(
            store: _store as! UsageStore,
            settings: _settings as! SettingsStore
        )
        .environment(\.colorScheme, .dark)
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
