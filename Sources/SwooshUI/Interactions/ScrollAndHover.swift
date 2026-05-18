// SwooshUI/Interactions/ScrollAndHover.swift — Scroll + hover polish (0.4A)
//
// Production-ready wrappers for the macOS 14+ / iOS 17+ scroll-transition
// API and the macOS 26 hover-effect family. Apply via view modifiers; the
// implementations degrade cleanly on older OSes.

import SwiftUI

// MARK: - Scroll fade-in

public struct SwooshScrollFadeIn: ViewModifier {
    /// How far below resting position the view starts when it enters.
    public let yOffset: CGFloat
    /// Opacity at the leading edge of the transition.
    public let startOpacity: Double

    public func body(content: Content) -> some View {
        content.scrollTransition(.animated.threshold(.visible(0.2))) { view, phase in
            view
                .opacity(phase.isIdentity ? 1 : startOpacity)
                .offset(y: phase.isIdentity ? 0 : yOffset)
                .scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
    }
}

public extension View {
    /// Fade + slide rows in as they enter the scroll viewport. The numbers
    /// match Swoosh's overall motion vocabulary (short distance, near-opaque
    /// start), so lists feel cohesive across panes.
    func swooshScrollFadeIn(yOffset: CGFloat = 18, startOpacity: Double = 0.0) -> some View {
        modifier(SwooshScrollFadeIn(yOffset: yOffset, startOpacity: startOpacity))
    }
}

// MARK: - Snap-paging horizontal carousel

public extension View {
    /// Apply paged snap-to-row behavior on a horizontal scroll view.
    /// Use inside `ScrollView(.horizontal)` with `.scrollTargetLayout()` on
    /// the inner stack and `.swooshSnapPaging()` on the scrollview itself.
    func swooshSnapPaging() -> some View {
        self.scrollTargetBehavior(.viewAligned)
    }
}

// MARK: - Hover lift

public struct SwooshHoverLift: ViewModifier {
    public let scale: CGFloat
    public let elevation: CGFloat

    @State private var isHovered = false

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1)
            .shadow(color: .black.opacity(isHovered ? 0.18 : 0),
                    radius: isHovered ? elevation : 0,
                    x: 0, y: isHovered ? elevation * 0.4 : 0)
            .animation(.smooth(duration: 0.25), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

public extension View {
    /// Subtle pointer-driven lift. Pair with `swooshGlass()` for the full
    /// "card responds to my cursor" feel.
    func swooshHoverLift(scale: CGFloat = 1.02, elevation: CGFloat = 12) -> some View {
        modifier(SwooshHoverLift(scale: scale, elevation: elevation))
    }
}

// MARK: - Hover-effect bridge (macOS 26 brought iPad hover effects to Mac)

public extension View {
    /// Apply the system hover effect. Defaults to `.automatic`. On platforms
    /// without `hoverEffect` (notably macOS even on 26), falls back to
    /// the manual `swooshHoverLift` so the surface still feels responsive.
    @ViewBuilder
    func swooshHoverEffect(_ effect: SwooshHoverEffectKind = .automatic) -> some View {
        #if os(iOS) || os(visionOS)
        if #available(iOS 17.0, *) {
            switch effect {
            case .automatic:
                self.hoverEffect(.automatic)
            case .highlight:
                self.hoverEffect(.highlight)
            case .lift:
                self.hoverEffect(.lift)
            }
        } else {
            self
        }
        #else
        self.swooshHoverLift()
        #endif
    }
}

/// Variant matching the SwiftUI options on macOS 14+/iOS 17+.
public enum SwooshHoverEffectKind: Sendable {
    case automatic
    case highlight
    case lift
}

// MARK: - Continuous corner radius helper

public extension View {
    /// Continuous corner radius — sharper at the corner, smoother in the curve.
    /// Matches Apple's reference design on hardware/SF Symbols.
    func swooshContinuousCorner(radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
