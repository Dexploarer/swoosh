// SwooshUI/AgentShell/AgentShellPolish.swift — 0.9R Polish micro-views
//
// Small reusable views consumed by AgentShellView + VoicePillScene to
// elevate the listening / sync / typing states. Each piece is isolated
// so the parent view's structure stays legible.
//
//   • VoiceWaveformView     — animated bars driven by SpeechCapture audio level.
//   • ListeningPulse        — soft cyan halo around the mic when listening.
//   • SyncBadge             — ONLINE / OFFLINE / QUEUED state chip.
//   • EmptyStateDot         — gentle pulsing dot for the empty chat thread.

import SwiftUI
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Voice waveform
// ═══════════════════════════════════════════════════════════════════

/// Animated bars that respond to live mic audio level. Drives off a
/// scalar in [0,1]; smooths internally so the bars don't twitch.
public struct VoiceWaveformView: View {

    public let level: Float            // Current audio level [0,1]
    public let active: Bool            // Whether listening — when false, bars rest at 0
    public let barCount: Int
    public let accent: NeonAccent

    @State private var phases: [Double] = []
    @State private var smoothedLevel: Double = 0

    public init(level: Float, active: Bool, barCount: Int = 14, accent: NeonAccent = .cyan) {
        self.level = level
        self.active = active
        self.barCount = barCount
        self.accent = accent
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(accent.color.opacity(active ? 0.9 : 0.32))
                    .frame(width: 2.5, height: barHeight(for: i))
                    .animation(.spring(duration: 0.18), value: smoothedLevel)
                    .animation(.easeInOut(duration: 0.15), value: phases)
            }
        }
        .frame(height: 22)
        .onChange(of: level) { _, newLevel in
            smoothedLevel = smoothedLevel * 0.7 + Double(newLevel) * 0.3
        }
        .task {
            // Subtle perpetual jitter so bars don't look frozen between
            // audio updates. Stops when not listening.
            while !Task.isCancelled {
                if active {
                    phases = (0..<barCount).map { _ in Double.random(in: 0.4...1.0) }
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 4
        guard active else { return base }
        let phase = phases.indices.contains(index) ? phases[index] : 0.5
        let magnitude = max(smoothedLevel * phase * 22, 4)
        return CGFloat(magnitude)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Listening pulse
// ═══════════════════════════════════════════════════════════════════

/// A soft expanding cyan ring that pulses while listening. Wraps the
/// existing mic icon. Reduce-motion respected — collapses to a static
/// dim ring when motion is reduced.
public struct ListeningPulse: View {

    public let active: Bool
    public let accent: NeonAccent

    @State private var pulse: CGFloat = 0.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(active: Bool, accent: NeonAccent = .cyan) {
        self.active = active
        self.accent = accent
    }

    public var body: some View {
        Circle()
            .strokeBorder(accent.color.opacity(active ? 0.45 : 0), lineWidth: 1.5)
            .scaleEffect(reduceMotion ? 1 : pulse)
            .opacity(active ? 1 : 0)
            .frame(width: 36, height: 36)
            .onChange(of: active) { _, isActive in
                if isActive && !reduceMotion {
                    withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                        pulse = 1.4
                    }
                } else {
                    pulse = 0.6
                }
            }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Sync badge
// ═══════════════════════════════════════════════════════════════════

public enum SyncState: Sendable, Equatable {
    /// Daemon reachable, no pending sends.
    case online
    /// Daemon unreachable; future sends will queue.
    case offline
    /// `n` sends are queued waiting for the daemon.
    case queued(Int)

    public var label: String {
        switch self {
        case .online:        return "online"
        case .offline:       return "offline"
        case .queued(let n): return "queued · \(n)"
        }
    }

    public var accent: NeonAccent {
        switch self {
        case .online: return .green
        case .offline, .queued: return .gold
        }
    }
}

public struct SyncBadge: View {
    public let state: SyncState

    public init(state: SyncState) { self.state = state }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state.accent.color)
                .frame(width: 5, height: 5)
                .shadow(color: state.accent.color.opacity(0.7), radius: 3)
            Text(state.label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .overlay(
            Capsule().strokeBorder(
                state.accent.color.opacity(0.3),
                lineWidth: 0.5
            )
        )
        .clipShape(Capsule())
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Empty state dot
// ═══════════════════════════════════════════════════════════════════

/// Single quiet pulsing dot used in the "Ask anything." empty state.
public struct EmptyStateDot: View {

    @State private var on: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        Circle()
            .fill(SwooshNeonTokens.Accent.cyan.opacity(on ? 0.9 : 0.4))
            .frame(width: 6, height: 6)
            .shadow(
                color: SwooshNeonTokens.Accent.cyan.opacity(on ? 0.7 : 0.2),
                radius: on ? 6 : 2
            )
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    withAnimation(.easeInOut(duration: 0.8)) { on.toggle() }
                }
            }
    }
}
