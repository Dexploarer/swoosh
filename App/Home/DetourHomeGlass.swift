// DetourHomeGlass.swift — shared Detour liquid glass treatments (0.5A)

import SwiftUI

extension View {
    func detourLiquidGlass(
        cornerRadius: CGFloat = 24,
        tint: Color = .white.opacity(0.045),
        stroke: Color = .white.opacity(0.10)
    ) -> some View {
        modifier(DetourLiquidGlassModifier(cornerRadius: cornerRadius, tint: tint, stroke: stroke))
    }
}

private struct DetourLiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let stroke: Color

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(tint)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
    }
}
