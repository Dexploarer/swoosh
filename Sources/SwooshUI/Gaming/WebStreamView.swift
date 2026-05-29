// SwooshUI/Gaming/WebStreamView.swift — SwiftUI wrapper for WKWebView cloud gaming
//
// NSViewRepresentable that embeds WebGameBridge's WKWebView directly
// into the SwiftUI gaming pane. Manages the lifecycle: configure → load
// → frame capture loop → cleanup. The agent hooks into frame capture
// and input injection through the bridge actor.
// 0.9T – May 2026

#if os(macOS)

import SwiftUI
import WebKit
import SwooshCloudGaming
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - WebStreamView
// ═══════════════════════════════════════════════════════════════════

/// SwiftUI wrapper that embeds a WKWebView driven by `WebGameBridge`.
/// Usage: `WebStreamView(service: .xboxCloud, onStatusChange: { ... })`
public struct WebStreamView: NSViewRepresentable {

    let service: CloudGamingService
    let bridge: WebGameBridge
    var onStatusChange: ((StreamStatus) -> Void)?

    public init(
        service: CloudGamingService,
        bridge: WebGameBridge,
        onStatusChange: ((StreamStatus) -> Void)? = nil
    ) {
        self.service = service
        self.bridge = bridge
        self.onStatusChange = onStatusChange
    }

    public func makeNSView(context: Context) -> WKWebView {
        let wv = bridge.configureWebView()
        wv.allowsBackForwardNavigationGestures = true
        context.coordinator.bridge = bridge
        context.coordinator.onStatusChange = onStatusChange
        bridge.loadService()
        return wv
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        // Nothing to update — bridge manages state
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    public final class Coordinator: NSObject {
        var bridge: WebGameBridge?
        var onStatusChange: ((StreamStatus) -> Void)?
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Stream status overlay
// ═══════════════════════════════════════════════════════════════════

/// Overlay that shows connection status, FPS, and an "Agent Active" badge.
struct StreamStatusOverlay: View {
    let status: StreamStatus
    let fps: Double
    let agentActive: Bool

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                // Status pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.7), radius: 4)
                    Text(statusText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(VoltPaper.foreground)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())

                // FPS badge
                if fps > 0 {
                    Text("\(Int(fps)) FPS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(VoltPaper.foreground.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer()

                // Agent badge
                if agentActive {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 10, weight: .bold))
                        Text("AGENT")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundStyle(VoltPaper.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(VoltPaper.accent.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(VoltPaper.accent.opacity(0.5), lineWidth: 1))
                }
            }
            .padding(12)

            Spacer()
        }
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: VoltPaper.mutedFg
        case .connecting:   VoltPaper.Chart.c4
        case .authenticating: VoltPaper.Chart.c4
        case .buffering:    VoltPaper.Chart.c4
        case .playing:      VoltPaper.accent
        case .paused:       VoltPaper.Chart.c4
        case .error:        VoltPaper.destructive
        }
    }

    private var statusText: String {
        switch status {
        case .disconnected:    "DISCONNECTED"
        case .connecting:      "CONNECTING…"
        case .authenticating:  "SIGNING IN…"
        case .buffering:       "BUFFERING…"
        case .playing:         "LIVE"
        case .paused:          "PAUSED"
        case .error:           "ERROR"
        }
    }
}

#endif
