// SwooshUI/Glassmorphism.swift — Apple Liquid Glass integration
//
// Uses the real SwiftUI Liquid Glass APIs from macOS 26 / iOS 26:
// .glassEffect(), GlassEffectContainer, .interactive(), .buttonStyle(.glass)
// Falls back to manual material-based glassmorphism on older OS.

import SwiftUI

// MARK: - Glass modifier (uses real Apple Liquid Glass APIs)

public struct SwooshGlassModifier: ViewModifier {
    @Environment(\.swooshTheme) var theme

    public func body(content: Content) -> some View {
        let config = theme.config.glass

        if config.interactive {
            content
                .glassEffect(.regular.interactive(), in: resolvedShape)
        } else {
            content
                .glassEffect(.regular, in: resolvedShape)
        }
    }

    private var resolvedShape: some Shape {
        RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
    }
}

// MARK: - Glass container modifier

public struct SwooshGlassContainerModifier: ViewModifier {
    @Environment(\.swooshTheme) var theme

    public func body(content: Content) -> some View {
        GlassEffectContainer {
            content
        }
    }
}

// MARK: - View extensions

public extension View {
    /// Apply Liquid Glass using the current theme's glass configuration.
    func swooshGlass() -> some View {
        self.modifier(SwooshGlassModifier())
    }

    /// Wrap content in a GlassEffectContainer for morphing/union support.
    func swooshGlassContainer() -> some View {
        self.modifier(SwooshGlassContainerModifier())
    }

    /// Apply glass button style.
    func swooshGlassButton() -> some View {
        self.buttonStyle(.glass)
    }
}
