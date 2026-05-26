// DetourMacApp.swift — first rebuilt macOS onboarding surface (0.5A)

import AppKit
import SwiftUI

@main
struct DetourMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = OnboardingStore()
    @StateObject private var speech = DetourSpeechService()

    var body: some Scene {
        WindowGroup {
            DetourOnboardingNativeView(
                store: store,
                speech: speech,
                onExit: { DetourWindowActions.minimizeMainWindow() }
            )
            .background(DetourWindowConfigurator())
            .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Detour") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }

        MenuBarExtra("Detour", systemImage: "sparkles") {
            DetourTrayMenuView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
enum DetourWindowActions {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("ai.swoosh.detour.main")

    static func showMainWindow() {
        guard let window = mainWindow() else { return }

        NSApp.setActivationPolicy(.regular)
        NSApp.presentationOptions = [.autoHideMenuBar]
        NSApp.activate(ignoringOtherApps: true)

        if window.isMiniaturized {
            window.deminiaturize(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func minimizeMainWindow() {
        guard let window = mainWindow(), window.isVisible, !window.isMiniaturized else { return }
        window.miniaturize(nil)
    }

    static func markAsMainWindow(_ window: NSWindow) {
        window.identifier = mainWindowIdentifier
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier == mainWindowIdentifier }
            ?? NSApp.mainWindow
            ?? NSApp.keyWindow
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockIcon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DetourWindowActions.showMainWindow()
        return false
    }

    private func applyDockIcon() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }
}
