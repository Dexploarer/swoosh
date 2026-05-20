// SwooshUI/Themes/Choreography.swift — Entrance + state animations (0.4A)
//
// Wraps `PhaseAnimator` and `KeyframeAnimator` in named modifiers for the
// motion vocabulary the rest of the app speaks: a quick fade-up-with-scale
// on hero entry, a staggered cascade for list rows, and a celebratory
// keyframe sequence on save/approve confirmations.

import SwiftUI

// MARK: - Entrance phases

public enum SwooshEntrancePhase: CaseIterable {
    case before
    case settling
    case rest

    public var opacity: Double {
        switch self {
        case .before:   return 0
        case .settling: return 0.6
        case .rest:     return 1
        }
    }

    public var yOffset: CGFloat {
        switch self {
        case .before:   return 24
        case .settling: return 6
        case .rest:     return 0
        }
    }

    public var scale: CGFloat {
        switch self {
        case .before:   return 0.96
        case .settling: return 0.99
        case .rest:     return 1
        }
    }
}

public struct SwooshEntranceModifier: ViewModifier {
    @State private var triggered = false

    public func body(content: Content) -> some View {
        content.phaseAnimator(SwooshEntrancePhase.allCases, trigger: triggered) { view, phase in
            view
                .opacity(phase.opacity)
                .offset(y: phase.yOffset)
                .scaleEffect(phase.scale)
        } animation: { phase in
            switch phase {
            case .before:   return .smooth(duration: 0.0)
            case .settling: return .spring(duration: 0.35, bounce: 0.15)
            case .rest:     return .spring(duration: 0.45, bounce: 0.25)
            }
        }
        .onAppear { triggered = true }
    }
}

public extension View {
    /// Once-per-appear entrance: fade up, settle, rest. Cheap and tasteful.
    func swooshEntrance() -> some View {
        modifier(SwooshEntranceModifier())
    }
}

// MARK: - Staggered cascade for lists

public struct SwooshStaggeredCascade: ViewModifier {
    let index: Int
    let total: Int
    let baseDelay: Double

    @State private var visible = false

    public func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .scaleEffect(visible ? 1 : 0.98)
            .animation(
                .spring(duration: 0.4, bounce: 0.18)
                    .delay(Double(index) * baseDelay),
                value: visible
            )
            .onAppear { visible = true }
    }
}

public extension View {
    /// Stagger this row's entrance based on its index in a list.
    func swooshStagger(at index: Int, of total: Int, baseDelay: Double = 0.04) -> some View {
        modifier(SwooshStaggeredCascade(index: index, total: total, baseDelay: baseDelay))
    }
}

// MARK: - Celebration keyframes

public struct SwooshCelebrationTrack: Equatable, Sendable {
    public var scale: CGFloat = 1
    public var rotation: Angle = .zero
    public var glow: Double = 0

    public init(scale: CGFloat = 1, rotation: Angle = .zero, glow: Double = 0) {
        self.scale = scale
        self.rotation = rotation
        self.glow = glow
    }
}

public struct SwooshCelebrateModifier<Trigger: Equatable & Sendable>: ViewModifier {
    let trigger: Trigger

    public func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: SwooshCelebrationTrack(), trigger: trigger) { view, track in
            view
                .scaleEffect(track.scale)
                .rotationEffect(track.rotation)
                .shadow(color: .accentColor.opacity(track.glow), radius: 16 * track.glow)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.0,  duration: 0.0)
                SpringKeyframe(1.18, duration: 0.18, spring: .bouncy)
                SpringKeyframe(1.0,  duration: 0.45, spring: .smooth)
            }
            KeyframeTrack(\.rotation) {
                CubicKeyframe(.zero, duration: 0.0)
                CubicKeyframe(.degrees(-6), duration: 0.1)
                SpringKeyframe(.degrees(6),  duration: 0.2, spring: .bouncy)
                SpringKeyframe(.zero, duration: 0.35, spring: .smooth)
            }
            KeyframeTrack(\.glow) {
                CubicKeyframe(0.0, duration: 0.0)
                CubicKeyframe(1.0, duration: 0.15)
                CubicKeyframe(0.0, duration: 0.55)
            }
        }
    }
}

public extension View {
    /// Play a celebratory keyframe routine when `trigger` changes — used on
    /// save/approve/pinned confirmations.
    func swooshCelebrate<T: Equatable & Sendable>(on trigger: T) -> some View {
        modifier(SwooshCelebrateModifier(trigger: trigger))
    }
}
