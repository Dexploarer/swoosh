// SwooshUI/ThemeManager.swift — User-customizable dynamic theme engine
//
// Fully customizable via ~/.swoosh/theme.json
// Supports: colors, glass, layout, typography, animations
// Hot-reloads from disk. Falls back to system defaults.

import SwiftUI
import Foundation

// MARK: - User-editable configuration (Codable from JSON)

public struct SwooshThemeConfig: Codable, Sendable, Equatable {
    public struct Colors: Codable, Sendable, Equatable {
        public var accent: String
        public var secondaryAccent: String
        public var background: String
        public var surface: String
        public var textPrimary: String
        public var textSecondary: String
        public var success: String
        public var warning: String
        public var error: String
        public var info: String
    }

    public struct Glass: Codable, Sendable, Equatable {
        /// "regular", "clear", "identity"
        public var variant: String
        /// Interactive: responds to touch/pointer
        public var interactive: Bool
        /// Shape: "capsule", "roundedRect", "circle"
        public var shape: String
        /// Union: group multiple glass elements into one
        public var enableUnion: Bool
    }

    public struct Layout: Codable, Sendable, Equatable {
        public var cornerRadius: CGFloat
        public var spacing: CGFloat
        public var padding: CGFloat
        public var borderWidth: CGFloat
    }

    public struct Typography: Codable, Sendable, Equatable {
        public var headlineSize: CGFloat
        public var bodySize: CGFloat
        public var captionSize: CGFloat
        public var monospacedCode: Bool
        public var fontDesign: String  // "default", "rounded", "monospaced", "serif"
    }

    public struct Animations: Codable, Sendable, Equatable {
        public var enableMorphing: Bool
        public var enableHoverEffects: Bool
        public var springDuration: Double
        public var springBounce: Double
    }

    public var name: String
    public var colorScheme: String  // "system", "light", "dark"
    public var colors: Colors
    public var glass: Glass
    public var layout: Layout
    public var typography: Typography
    public var animations: Animations

    /// Default "Liquid Glass" configuration
    public static let liquidGlassDefault = SwooshThemeConfig(
        name: "Liquid Glass",
        colorScheme: "system",
        colors: Colors(
            accent: "#00D4FF",
            secondaryAccent: "#7B2FBE",
            background: "#000000",
            surface: "#1A1A2E",
            textPrimary: "#FFFFFF",
            textSecondary: "#A0A0B0",
            success: "#00E676",
            warning: "#FFD600",
            error: "#FF5252",
            info: "#448AFF"
        ),
        glass: Glass(
            variant: "regular",
            interactive: true,
            shape: "roundedRect",
            enableUnion: true
        ),
        layout: Layout(
            cornerRadius: 20,
            spacing: 16,
            padding: 20,
            borderWidth: 0.5
        ),
        typography: Typography(
            headlineSize: 28,
            bodySize: 15,
            captionSize: 12,
            monospacedCode: true,
            fontDesign: "rounded"
        ),
        animations: Animations(
            enableMorphing: true,
            enableHoverEffects: true,
            springDuration: 0.5,
            springBounce: 0.3
        )
    )
}

// MARK: - Hex color extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Resolved theme (compiled from config)

public struct SwooshTheme: Sendable {
    public let config: SwooshThemeConfig

    // Resolved colors
    public var accent: Color { Color(hex: config.colors.accent) }
    public var secondaryAccent: Color { Color(hex: config.colors.secondaryAccent) }
    public var background: Color { Color(hex: config.colors.background) }
    public var surface: Color { Color(hex: config.colors.surface) }
    public var textPrimary: Color { Color(hex: config.colors.textPrimary) }
    public var textSecondary: Color { Color(hex: config.colors.textSecondary) }
    public var success: Color { Color(hex: config.colors.success) }
    public var warning: Color { Color(hex: config.colors.warning) }
    public var error: Color { Color(hex: config.colors.error) }
    public var info: Color { Color(hex: config.colors.info) }

    // Layout
    public var cornerRadius: CGFloat { config.layout.cornerRadius }
    public var spacing: CGFloat { config.layout.spacing }
    public var padding: CGFloat { config.layout.padding }
    public var borderWidth: CGFloat { config.layout.borderWidth }

    // Typography
    public var headlineFont: Font {
        .system(size: config.typography.headlineSize, weight: .bold, design: fontDesign)
    }
    public var bodyFont: Font {
        .system(size: config.typography.bodySize, design: fontDesign)
    }
    public var captionFont: Font {
        .system(size: config.typography.captionSize, design: fontDesign)
    }
    public var codeFont: Font {
        config.typography.monospacedCode
            ? .system(size: config.typography.bodySize, design: .monospaced)
            : bodyFont
    }

    private var fontDesign: Font.Design {
        switch config.typography.fontDesign {
        case "rounded":    return .rounded
        case "monospaced": return .monospaced
        case "serif":      return .serif
        default:           return .default
        }
    }

    // Animation
    public var springAnimation: Animation {
        .spring(duration: config.animations.springDuration, bounce: config.animations.springBounce)
    }

    public init(from config: SwooshThemeConfig) {
        self.config = config
    }

    public static let `default` = SwooshTheme(from: .liquidGlassDefault)
}

// MARK: - Theme manager

@Observable
public final class ThemeManager {
    public var currentTheme: SwooshTheme

    public init(theme: SwooshTheme = .default) {
        self.currentTheme = theme
    }

    /// Load theme from user's JSON file (e.g. ~/.swoosh/theme.json)
    public func load(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(SwooshThemeConfig.self, from: data)
            self.currentTheme = SwooshTheme(from: config)
        } catch {
            // Gracefully remain on current theme
            print("[SwooshUI] Failed to load theme: \(error)")
        }
    }

    /// Update from a raw JSON string (for live preview / in-app editor)
    public func update(fromJSON json: String) {
        guard let data = json.data(using: .utf8),
              let config = try? JSONDecoder().decode(SwooshThemeConfig.self, from: data)
        else { return }
        self.currentTheme = SwooshTheme(from: config)
    }

    /// Update from a config struct
    public func update(with config: SwooshThemeConfig) {
        self.currentTheme = SwooshTheme(from: config)
    }

    /// Save current theme to disk
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(currentTheme.config)
        try data.write(to: url)
    }
}

// MARK: - Environment injection

private struct SwooshThemeKey: EnvironmentKey {
    static let defaultValue: SwooshTheme = .default
}

public extension EnvironmentValues {
    var swooshTheme: SwooshTheme {
        get { self[SwooshThemeKey.self] }
        set { self[SwooshThemeKey.self] = newValue }
    }
}

public extension View {
    func swooshTheme(_ theme: SwooshTheme) -> some View {
        environment(\.swooshTheme, theme)
    }
}
