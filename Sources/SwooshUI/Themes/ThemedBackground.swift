// SwooshUI/Themes/ThemedBackground.swift — Mesh-gradient backdrop (0.4A)
//
// Applies the active theme's `Background` dimension as a window-spanning
// backdrop. Uses `MeshGradient` (macOS 15+/iOS 18+) for the rich variants and
// drifts the control points over time for `meshAnimated`. Falls back to a
// solid fill for `kind == "solid"` or when the system can't render meshes.

import SwiftUI

// MARK: - Modifier

public struct SwooshThemedBackgroundModifier: ViewModifier {
    @Environment(\.swooshTheme) var theme

    public func body(content: Content) -> some View {
        content
            .background(
                SwooshThemedBackgroundView()
                    .ignoresSafeArea()
            )
    }
}

public extension View {
    /// Render the theme's resolved background behind this view's bounds,
    /// ignoring safe areas. Pair with `swooshGlass()` on foreground cards.
    func swooshThemedBackground() -> some View {
        modifier(SwooshThemedBackgroundModifier())
    }
}

// MARK: - Renderer

public struct SwooshThemedBackgroundView: View {
    @Environment(\.swooshTheme) var theme
    @State private var phase: Double = 0

    public init() {}

    public var body: some View {
        switch theme.backgroundKind {
        case .solid:
            theme.backgroundFallback
        case .mesh:
            staticMesh
        case .meshAnimated:
            animatedMesh
        }
    }

    // MARK: Static mesh

    @ViewBuilder
    private var staticMesh: some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            MeshGradient(
                width: 3,
                height: 3,
                points: theme.backgroundMeshPoints,
                colors: theme.backgroundMeshColors
            )
        } else {
            // Graceful fallback when MeshGradient is unavailable.
            theme.backgroundFallback
        }
    }

    // MARK: Animated mesh

    @ViewBuilder
    private var animatedMesh: some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: driftedPoints(time: t),
                    colors: theme.backgroundMeshColors
                )
            }
        } else {
            theme.backgroundFallback
        }
    }

    /// Drift the four corner-adjacent edge points around the center to give
    /// the mesh a slow breathing motion. Corners are anchored so the canvas
    /// stays fully covered.
    private func driftedPoints(time t: TimeInterval) -> [SIMD2<Float>] {
        let period = max(theme.config.background.animationDuration, 0.5)
        let phase = (t.truncatingRemainder(dividingBy: period)) / period * .pi * 2
        let amp: Float = 0.08
        let base = theme.backgroundMeshPoints
        guard base.count == 9 else { return base }
        let s = Float(sin(phase))
        let c = Float(cos(phase))
        return [
            base[0],
            SIMD2(base[1].x + s * amp, base[1].y),
            base[2],
            SIMD2(base[3].x, base[3].y + c * amp),
            SIMD2(base[4].x + s * amp * 0.5, base[4].y + c * amp * 0.5),
            SIMD2(base[5].x, base[5].y - c * amp),
            base[6],
            SIMD2(base[7].x - s * amp, base[7].y),
            base[8],
        ]
    }
}
