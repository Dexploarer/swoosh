// DetourWindowConfigurator.swift — key-safe transparent Detour launch window (0.5A)

import AppKit
import SwiftUI

enum DetourWindowStyle {
    case onboarding
    case home
}

struct DetourWindowConfigurator: NSViewRepresentable {
    var style: DetourWindowStyle = .onboarding

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window, coordinator: context.coordinator, style: style)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator, style: style)
        }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator, style: DetourWindowStyle) {
        guard let window else { return }

        DetourWindowActions.markAsMainWindow(window)

        if coordinator.configuredStyle != style {
            coordinator.configuredStyle = style
            switch style {
            case .onboarding:
                configureOnboarding(window)
            case .home:
                configureHome(window)
            }
        }

        guard !coordinator.didInitialShow else { return }
        coordinator.didInitialShow = true
        DetourWindowActions.showMainWindow()
    }

    final class Coordinator {
        var didInitialShow = false
        var configuredStyle: DetourWindowStyle?
    }

    private func configureOnboarding(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.miniaturizable)
        window.isMovableByWindowBackground = false
        window.hasShadow = false
        window.level = .normal
        window.collectionBehavior.insert(.canJoinAllSpaces)

        if let screen = window.screen ?? NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
    }

    private func configureHome(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.title = "Detour"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.level = .normal
        window.collectionBehavior.remove(.canJoinAllSpaces)
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.minSize = NSSize(width: 980, height: 660)
        window.center()
    }
}
