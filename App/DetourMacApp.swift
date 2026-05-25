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
                onExit: { DetourWindowActions.minimizeVisibleWindows() }
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
    }
}

@MainActor
private enum DetourWindowActions {
    static func minimizeVisibleWindows() {
        let targetWindows = [
            NSApp.keyWindow,
            NSApp.mainWindow,
            NSApp.windows.first { $0.isVisible && !$0.isMiniaturized }
        ].compactMap { $0 }

        if let window = targetWindows.first {
            window.miniaturize(nil)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        bringIntroForward()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.bringIntroForward()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringIntroForward()
        return true
    }

    private func bringIntroForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.presentationOptions = [.autoHideMenuBar]
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.forEach { window in
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}
