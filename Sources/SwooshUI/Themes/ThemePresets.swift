// SwooshUI/Themes/ThemePresets.swift — Built-in theme library (0.4A)
//
// Eight curated theme presets that all share the same `SwooshThemeConfig`
// schema so the visual editor can tweak any of them. Picking a preset is
// non-destructive: the user can edit any value afterwards and save the result
// as their own `~/.swoosh/theme.json`.

import Foundation

public struct SwooshThemePreset: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let tagline: String
    public let config: SwooshThemeConfig

    public init(id: String, displayName: String, tagline: String, config: SwooshThemeConfig) {
        self.id = id
        self.displayName = displayName
        self.tagline = tagline
        self.config = config
    }
}

public extension SwooshThemeConfig {
    /// All built-in presets, in display order.
    static let builtInPresets: [SwooshThemePreset] = [
        .init(
            id: "liquid-glass",
            displayName: "Liquid Glass",
            tagline: "The Swoosh signature — cyan + violet on deep ink",
            config: .liquidGlassDefault
        ),
        .init(
            id: "midnight",
            displayName: "Midnight",
            tagline: "Deep blue minimal, single accent",
            config: midnight
        ),
        .init(
            id: "aurora",
            displayName: "Aurora",
            tagline: "Cyan, violet, magenta — animated",
            config: aurora
        ),
        .init(
            id: "mocha",
            displayName: "Mocha",
            tagline: "Warm browns, soft amber accent",
            config: mocha
        ),
        .init(
            id: "solarized",
            displayName: "Solarized",
            tagline: "The classic dev palette",
            config: solarized
        ),
        .init(
            id: "daylight",
            displayName: "Daylight",
            tagline: "Bright surfaces, ink-on-paper",
            config: daylight
        ),
        .init(
            id: "forest",
            displayName: "Forest",
            tagline: "Sage and pine on dark moss",
            config: forest
        ),
        .init(
            id: "sunset",
            displayName: "Sunset",
            tagline: "Coral, rose, amber",
            config: sunset
        ),
    ]

    static let midnight = SwooshThemeConfig(
        name: "Midnight",
        colorScheme: "dark",
        colors: Colors(
            accent: "#5E9CFF",
            secondaryAccent: "#3A6BD9",
            background: "#050A1A",
            surface: "#0E1730",
            textPrimary: "#E8ECF8",
            textSecondary: "#7E8AB0",
            success: "#5BE0A6",
            warning: "#F5C46A",
            error: "#F37272",
            info: "#5E9CFF"
        ),
        glass: Glass(variant: "regular", interactive: true, shape: "roundedRect", enableUnion: true),
        layout: Layout(cornerRadius: 18, spacing: 14, padding: 18, borderWidth: 0.5),
        typography: Typography(headlineSize: 26, bodySize: 14, captionSize: 11, monospacedCode: true, fontDesign: "default"),
        animations: Animations(enableMorphing: true, enableHoverEffects: true, springDuration: 0.45, springBounce: 0.2),
        background: Background(
            kind: "mesh",
            meshPoints: SwooshThemeConfig.uniformMeshPoints,
            meshColors: [
                "#050A1A", "#0A1330", "#050A1A",
                "#0C1846", "#16205C", "#0C1846",
                "#050A1A", "#0A1330", "#050A1A",
            ],
            animationDuration: 20,
            fallbackColor: "#050A1A"
        )
    )

    static let aurora = SwooshThemeConfig(
        name: "Aurora",
        colorScheme: "dark",
        colors: Colors(
            accent: "#34E5D2",
            secondaryAccent: "#B26BFF",
            background: "#0B0716",
            surface: "#1A0F2C",
            textPrimary: "#F4ECFF",
            textSecondary: "#9C8FB8",
            success: "#34E5D2",
            warning: "#FFD166",
            error: "#FF6B9D",
            info: "#7DD3FC"
        ),
        glass: Glass(variant: "regular", interactive: true, shape: "roundedRect", enableUnion: true),
        layout: Layout(cornerRadius: 22, spacing: 16, padding: 20, borderWidth: 0.5),
        typography: Typography(headlineSize: 28, bodySize: 15, captionSize: 12, monospacedCode: true, fontDesign: "rounded"),
        animations: Animations(enableMorphing: true, enableHoverEffects: true, springDuration: 0.55, springBounce: 0.35),
        background: Background(
            kind: "meshAnimated",
            meshPoints: SwooshThemeConfig.uniformMeshPoints,
            meshColors: [
                "#0B0716", "#1A0F2C", "#0B0716",
                "#1A4A6E", "#5C2B91", "#9C2E73",
                "#0B0716", "#2C144E", "#0B0716",
            ],
            animationDuration: 14,
            fallbackColor: "#0B0716"
        )
    )

    static let mocha = SwooshThemeConfig(
        name: "Mocha",
        colorScheme: "dark",
        colors: Colors(
            accent: "#E4B370",
            secondaryAccent: "#C97B5E",
            background: "#1E1612",
            surface: "#2C201A",
            textPrimary: "#F1E6D9",
            textSecondary: "#A89884",
            success: "#A6C788",
            warning: "#E4B370",
            error: "#D96B5E",
            info: "#8FB5C9"
        ),
        glass: Glass(variant: "regular", interactive: true, shape: "roundedRect", enableUnion: true),
        layout: Layout(cornerRadius: 16, spacing: 14, padding: 18, borderWidth: 0.5),
        typography: Typography(headlineSize: 26, bodySize: 15, captionSize: 12, monospacedCode: true, fontDesign: "serif"),
        animations: Animations(enableMorphing: true, enableHoverEffects: true, springDuration: 0.5, springBounce: 0.25),
        background: Background(
            kind: "mesh",
            meshPoints: SwooshThemeConfig.uniformMeshPoints,
            meshColors: [
                "#1E1612", "#241A14", "#1E1612",
                "#2A1E16", "#3A2A1E", "#2A1E16",
                "#1E1612", "#241A14", "#1E1612",
            ],
            animationDuration: 22,
            fallbackColor: "#1E1612"
        )
    )

    static let solarized = SwooshThemeConfig(
        name: "Solarized",
        colorScheme: "dark",
        colors: Colors(
            accent: "#268BD2",
            secondaryAccent: "#2AA198",
            background: "#002B36",
            surface: "#073642",
            textPrimary: "#FDF6E3",
            textSecondary: "#93A1A1",
            success: "#859900",
            warning: "#B58900",
            error: "#DC322F",
            info: "#268BD2"
        ),
        glass: Glass(variant: "regular", interactive: false, shape: "roundedRect", enableUnion: false),
        layout: Layout(cornerRadius: 10, spacing: 12, padding: 16, borderWidth: 1),
        typography: Typography(headlineSize: 24, bodySize: 14, captionSize: 11, monospacedCode: true, fontDesign: "monospaced"),
        animations: Animations(enableMorphing: false, enableHoverEffects: true, springDuration: 0.35, springBounce: 0.15),
        background: Background(
            kind: "solid",
            meshPoints: SwooshThemeConfig.uniformMeshPoints,
            meshColors: Array(repeating: "#002B36", count: 9),
            animationDuration: 0,
            fallbackColor: "#002B36"
        )
    )

    static let daylight = SwooshThemeConfig(
        name: "Daylight",
        colorScheme: "light",
        colors: Colors(
            accent: "#0066CC",
            secondaryAccent: "#6A4FDB",
            background: "#F7F7FB",
            surface: "#FFFFFF",
            textPrimary: "#0E121A",
            textSecondary: "#5F6478",
            success: "#1A9E6D",
            warning: "#C58E00",
            error: "#C9293E",
            info: "#0066CC"
        ),
        glass: Glass(variant: "regular", interactive: true, shape: "roundedRect", enableUnion: true),
        layout: Layout(cornerRadius: 16, spacing: 14, padding: 18, borderWidth: 0.5),
        typography: Typography(headlineSize: 28, bodySize: 14, captionSize: 11, monospacedCode: true, fontDesign: "default"),
        animations: Animations(enableMorphing: true, enableHoverEffects: true, springDuration: 0.4, springBounce: 0.2),
        background: Background(
            kind: "mesh",
            meshPoints: SwooshThemeConfig.uniformMeshPoints,
            meshColors: [
                "#FFFFFF", "#F2F4FA", "#FFFFFF",
                "#EEF1F8", "#E7ECF6", "#EEF1F8",
                "#FFFFFF", "#F2F4FA", "#FFFFFF",
            ],
            animationDuration: 24,
            fallbackColor: "#F7F7FB"
        )
    )

    static let forest = SwooshThemeConfig(
        name: "Forest",
        colorScheme: "dark",
        colors: Colors(
            accent: "#7CC58F",
            secondaryAccent: "#4F8C5F",
            background: "#0E1A14",
            surface: "#16271F",
            textPrimary: "#E6F0E9",
            textSecondary: "#8AA396",
            success: "#7CC58F",
            warning: "#E4C064",
            error: "#D97A6C",
            info: "#83B5C2"
        ),
        glass: Glass(variant: "regular", interactive: true, shape: "roundedRect", enableUnion: true),
        layout: Layout(cornerRadius: 18, spacing: 14, padding: 18, borderWidth: 0.5),
        typography: Typography(headlineSize: 26, bodySize: 14, captionSize: 11, monospacedCode: true, fontDesign: "rounded"),
        animations: Animations(enableMorphing: true, enableHoverEffects: true, springDuration: 0.5, springBounce: 0.25),
        background: Background(
            kind: "mesh",
            meshPoints: SwooshThemeConfig.uniformMeshPoints,
            meshColors: [
                "#0E1A14", "#13241B", "#0E1A14",
                "#1A302A", "#234438", "#1A302A",
                "#0E1A14", "#13241B", "#0E1A14",
            ],
            animationDuration: 20,
            fallbackColor: "#0E1A14"
        )
    )

    static let sunset = SwooshThemeConfig(
        name: "Sunset",
        colorScheme: "dark",
        colors: Colors(
            accent: "#FF8E72",
            secondaryAccent: "#E04D8B",
            background: "#1A0E14",
            surface: "#2A1620",
            textPrimary: "#FFE9DF",
            textSecondary: "#B89095",
            success: "#9CC97E",
            warning: "#F4C661",
            error: "#E04D8B",
            info: "#8FB5D6"
        ),
        glass: Glass(variant: "regular", interactive: true, shape: "roundedRect", enableUnion: true),
        layout: Layout(cornerRadius: 22, spacing: 16, padding: 20, borderWidth: 0.5),
        typography: Typography(headlineSize: 30, bodySize: 15, captionSize: 12, monospacedCode: true, fontDesign: "rounded"),
        animations: Animations(enableMorphing: true, enableHoverEffects: true, springDuration: 0.55, springBounce: 0.4),
        background: Background(
            kind: "meshAnimated",
            meshPoints: SwooshThemeConfig.uniformMeshPoints,
            meshColors: [
                "#1A0E14", "#2A1620", "#1A0E14",
                "#7A2A4A", "#E04D8B", "#FF8E72",
                "#1A0E14", "#3A1C28", "#1A0E14",
            ],
            animationDuration: 12,
            fallbackColor: "#1A0E14"
        )
    )
}
