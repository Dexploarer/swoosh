// DetourWindowConfigurator.swift — key-safe transparent Detour launch window (0.5A)

import AppKit
import SwiftUI

struct DetourWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }

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

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
