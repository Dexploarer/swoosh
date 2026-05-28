// SwooshUI/Voice/DesktopOverlayScene.swift — 0.9R Desktop generative-UI overlay
//
// A frameless floating window that hosts the agent's emitted generative
// surfaces while voice mode is active. Sized to a reasonable hero card
// (~720×480) and pinned to the bottom-right by default; user can drag.
//
// Why a separate scene from the pill: surfaces are tall and content-rich.
// Mixing them into the bottom pill made the pill explode. Splitting them
// keeps the pill compact and the surface readable.
//
// "Computer use, browser, skills" — these are agent capabilities, not
// extra render paths. Any tool the agent invokes that emits a UI surface
// (via the SwooshGenerativeUI sentinel envelope) lands here automatically.

#if os(macOS)

import AppKit
import SwiftUI
import SwooshGenerativeUI

public struct DesktopOverlayScene: Scene {

    public static let windowID: String = "swoosh.desktop-overlay"

    private let shell: AgentShellModel

    public init(shell: AgentShellModel) {
        self.shell = shell
    }

    public var body: some Scene {
        Window("Swoosh Overlay", id: Self.windowID) {
            DesktopOverlayContainer(shell: shell)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultPosition(.bottomTrailing)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

private struct DesktopOverlayContainer: View {
    @Bindable var shell: AgentShellModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(width: 720, height: 480)
        .background(SwooshNeonTokens.Canvas.bg.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: SwooshNeonTokens.Radius.tile, style: .continuous)
                .strokeBorder(
                    SwooshNeonTokens.Accent.cyan.opacity(SwooshNeonTokens.Line.bright),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: SwooshNeonTokens.Radius.tile, style: .continuous))
        .shadow(
            color: SwooshNeonTokens.Accent.cyan.opacity(SwooshNeonTokens.Glow.focus),
            radius: SwooshNeonTokens.Glow.radius * 1.4
        )
        .padding(20)
        .background(WindowDragEnabler())
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            Text("AGENT SURFACE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            Spacer()
            if !shell.activeSurfaceID.isEmpty {
                Text(shell.activeSurfaceID)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
            windowControls
        }
        .padding(.horizontal, SwooshNeonTokens.Spacing.base + 6)
        .padding(.top, SwooshNeonTokens.Spacing.base + 4)
        .padding(.bottom, SwooshNeonTokens.Spacing.base)
    }

    private var windowControls: some View {
        HStack(spacing: 6) {
            OverlayControlButton(
                systemImage: "minus",
                accessibilityLabel: "Minimize"
            ) {
                NSApp.windows
                    .first { $0.title == "Swoosh Overlay" }?
                    .miniaturize(nil)
            }
            OverlayControlButton(
                systemImage: "xmark",
                accessibilityLabel: "Close"
            ) {
                dismissWindow(id: DesktopOverlayScene.windowID)
            }
        }
        .padding(.leading, SwooshNeonTokens.Spacing.base)
    }

    @ViewBuilder
    private var content: some View {
        if shell.surfaceHost.surfaces[shell.activeSurfaceID] != nil {
            ScrollView {
                GenerativeSurfaceView(
                    host: shell.surfaceHost,
                    surfaceID: shell.activeSurfaceID
                )
                .padding(SwooshNeonTokens.Spacing.base + 6)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            EmptyStateDot()
            Text("Waiting for the agent to emit a surface…")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            Text("Talk to it. Skills, browser, computer-use — whatever tool emits UI lands here.")
                .font(.system(size: 11))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Window controls

/// Small circular icon button for the overlay header — dims at rest,
/// highlights to cyan on hover with a subtle background fill.
private struct OverlayControlButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                    isHovered
                        ? SwooshNeonTokens.Accent.cyan
                        : SwooshNeonTokens.Canvas.text3
                )
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(
                            isHovered
                                ? SwooshNeonTokens.Accent.cyan.opacity(0.15)
                                : Color.clear
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Window drag

/// Invisible AppKit view that sets `isMovableByWindowBackground` on its
/// hosting `NSWindow`, giving the frameless overlay a title-bar-style drag
/// region on every non-interactive surface (Text, Spacer, background).
/// Interactive elements (buttons, scroll views) keep their own tracking
/// areas and work normally.
private struct WindowDragEnabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { EnablerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class EnablerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isMovableByWindowBackground = true
        }
    }
}

#endif
