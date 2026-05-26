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
            Group {
                if store.step == .complete {
                    DetourHomeView(store: store)
                } else {
                    DetourOnboardingNativeView(
                        store: store,
                        speech: speech,
                        onExit: { DetourWindowActions.minimizeMainWindow() }
                    )
                    .ignoresSafeArea()
                }
            }
            .background(DetourWindowConfigurator(style: store.step == .complete ? .home : .onboarding))
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

    static func expandForCanvas() {
        resizeMainWindow(to: NSSize(width: 1460, height: 900), minimum: NSSize(width: 1180, height: 720))
    }

    static func fitHomeWindow() {
        resizeMainWindow(to: NSSize(width: 1120, height: 760), minimum: NSSize(width: 980, height: 660))
    }

    static func markAsMainWindow(_ window: NSWindow) {
        window.identifier = mainWindowIdentifier
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier == mainWindowIdentifier }
            ?? NSApp.mainWindow
            ?? NSApp.keyWindow
    }

    private static func resizeMainWindow(to size: NSSize, minimum: NSSize) {
        guard let window = mainWindow() else { return }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        window.minSize = minimum
        window.setContentSize(size)
        var frame = window.frame
        frame.origin.x = center.x - frame.width / 2
        frame.origin.y = center.y - frame.height / 2
        if let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            frame.origin.x = min(max(frame.minX, screenFrame.minX), max(screenFrame.maxX - frame.width, screenFrame.minX))
            frame.origin.y = min(max(frame.minY, screenFrame.minY), max(screenFrame.maxY - frame.height, screenFrame.minY))
        }
        window.setFrame(frame, display: true, animate: true)
        showMainWindow()
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
