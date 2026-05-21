// SwooshUI/AgentShell/VoicePillScene.swift — 0.9R Floating voice pill
//
// A frameless, floating capsule that summons the agent shell in its most
// compact form. Resting state is a ~440×56 input row (mic + field +
// picker). When the agent responds with a generative surface or the chat
// grows, the pill expands downward into a panel keeping the same width.
//
// Wired into App.body as a top-level Scene. Open with:
//   @Environment(\.openWindow) var openWindow
//   openWindow(id: "swoosh.voice-pill")
//
// Designed for macOS 26 SwiftUI window APIs: `.windowStyle(.plain)`,
// `.windowLevel(.floating)`, `.windowResizability(.contentSize)`.

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI

public struct VoicePillScene: Scene {

    public static let windowID: String = "swoosh.voice-pill"

    private let shell: AgentShellModel

    public init(shell: AgentShellModel) {
        self.shell = shell
    }

    public var body: some Scene {
        Window("Swoosh Voice", id: Self.windowID) {
            VoicePillContainer(shell: shell)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultPosition(.top)
        .defaultLaunchBehavior(.suppressed)   // Don't open at app launch
        .restorationBehavior(.disabled)        // Don't re-summon from restore
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Container
// ═══════════════════════════════════════════════════════════════════

private struct VoicePillContainer: View {
    @Bindable var shell: AgentShellModel

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible compact shell. Min height of 56pt = just the
            // input row when there are no messages and no surface.
            AgentShellView(shell: shell, mode: .pill)
                .frame(width: 440)
                .frame(maxHeight: shell.isPillExpanded ? 360 : 56)
                .clipShape(RoundedRectangle(cornerRadius: SwooshNeonTokens.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SwooshNeonTokens.Radius.card, style: .continuous)
                        .strokeBorder(
                            SwooshNeonTokens.Accent.cyan.opacity(SwooshNeonTokens.Line.bright),
                            lineWidth: SwooshNeonTokens.Line.width
                        )
                )
                .shadow(
                    color: SwooshNeonTokens.Accent.cyan.opacity(
                        shell.voice == .listening
                            ? SwooshNeonTokens.Glow.active
                            : SwooshNeonTokens.Glow.focus
                    ),
                    radius: SwooshNeonTokens.Glow.radius
                )
                .animation(.spring(duration: 0.3), value: shell.isPillExpanded)
                .animation(.easeInOut(duration: 0.15), value: shell.voice)
        }
        .padding(SwooshNeonTokens.Spacing.base)
        .background(Color.clear)
        .onChange(of: shell.messages.count) { _, _ in
            // Any new message expands the pill so the response is visible.
            shell.isPillExpanded = true
        }
        .onChange(of: shell.surfaceHost.surfaces.count) { _, _ in
            // Any new surface also expands.
            shell.isPillExpanded = true
        }
    }
}

#endif
