// SwooshGenerativeUI/Tokens/SwooshNeonTokens.swift — 0.9R Neon design tokens
//
// "Neon line on pure black, with glow as the only form of elevation."
//
// Lives in SwooshGenerativeUI (zero internal deps) so both static SwooshUI
// screens and the agent-emitted UIRenderer consume the same tokens. Agent
// surfaces and human surfaces must look identical — one font, one accent,
// one glow scale.
//
// Three accents: cyan is the default; gold flags energy/heat/manifesting;
// green flags value/funds/approvals. Only one accent per surface — mixing
// is a rule violation, not a style choice.

import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Accent role
// ═══════════════════════════════════════════════════════════════════

/// The domain accent a surface adopts. Pick one per card / sheet / row;
/// never mix on a single surface.
public enum NeonAccent: String, Sendable, CaseIterable {
    /// Default. Every neutral interactive surface, every line, every line
    /// drawing icon at rest.
    case cyan

    /// Energy / heat / throughput. Manifesting passes, MLX inference,
    /// streaming load.
    case gold

    /// Value / funds / approvals / success states. Wallet, balances,
    /// completed flows.
    case green

    public var color: Color {
        switch self {
        case .cyan:  return SwooshNeonTokens.Accent.cyan
        case .gold:  return SwooshNeonTokens.Accent.gold
        case .green: return SwooshNeonTokens.Accent.green
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Tokens
// ═══════════════════════════════════════════════════════════════════

/// Typed design tokens. Use the view modifiers (`.neonTile(_:)`,
/// `.neonGlow(_:_:)`, `.neonHairline(_:_:)`) for normal consumption; access
/// raw values only when building new primitives.
public enum SwooshNeonTokens {

    // ── Canvas ──────────────────────────────────────────────────────

    public enum Canvas {
        /// Pure black. Universal background; no off-black, no near-black.
        public static let bg: Color = .black

        /// Primary text. Active state.
        public static let text1: Color = .white

        /// Body, secondary.
        public static let text2: Color = .white.opacity(0.64)

        /// Captions, dimension labels, "off" states.
        public static let text3: Color = .white.opacity(0.40)
    }

    // ── Accent ──────────────────────────────────────────────────────

    public enum Accent {
        /// Primary — every default interactive, every line, every
        /// selected state on a neutral surface.
        public static let cyan: Color = Color(red: 0x26 / 255.0, green: 0xE0 / 255.0, blue: 0xE8 / 255.0)

        /// Energy, heat, throughput, manifesting.
        public static let gold: Color = Color(red: 0xF2 / 255.0, green: 0xB5 / 255.0, blue: 0x30 / 255.0)

        /// Funds, value, approvals, success.
        public static let green: Color = Color(red: 0x3C / 255.0, green: 0xDF / 255.0, blue: 0x52 / 255.0)
    }

    // ── Glow scale (replaces shadow) ────────────────────────────────

    public enum Glow {
        /// Outline of a tile at rest. Barely there.
        public static let idle: Double = 0.20

        /// Hover / focus ring.
        public static let focus: Double = 0.40

        /// Pressed, selected, in-progress.
        public static let active: Double = 0.60

        /// Radius of the diffuse glow, in points.
        public static let radius: CGFloat = 18
    }

    // ── Line ────────────────────────────────────────────────────────

    public enum Line {
        /// Card outline at rest. The signature thin line.
        public static let dim: Double = 0.16

        /// Active / focused outline.
        public static let bright: Double = 0.56

        /// Internal divider — never accent-colored.
        public static let rule = Color.white.opacity(0.08)

        /// Outline stroke width.
        public static let width: CGFloat = 1
    }

    // ── Geometry ────────────────────────────────────────────────────

    public enum Radius {
        /// Inline cards — list rows, chips, banner cards.
        public static let card: CGFloat = 12

        /// Tile — app-icon-shaped squircle. Matches the reference glyphs.
        public static let tile: CGFloat = 22

        /// Pill CTA — outlined cyan pill matching Apple's pill geometry
        /// but with hairline outline + glow rather than blue fill.
        public static let pill: CGFloat = 980
    }

    public enum Spacing {
        /// Apple's 8pt base stays. Use multiples for normal spacing.
        public static let base: CGFloat = 8

        /// Tight cluster — chip group, mono row, picker trigger interior.
        public static let micro: CGFloat = 6
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - View modifiers
// ═══════════════════════════════════════════════════════════════════

public extension View {

    /// Wrap content in a neon tile — hairline outline, optional glow at
    /// rest, pure-black fill. The signature surface of the system.
    ///
    /// - Parameters:
    ///   - accent: which accent role the tile adopts.
    ///   - state: outline + glow intensity. `.idle` is the at-rest tile.
    ///   - shape: `.card` (12pt) or `.tile` (22pt — app-icon squircle).
    func neonTile(
        _ accent: NeonAccent = .cyan,
        state: NeonTileState = .idle,
        shape: NeonTileShape = .card
    ) -> some View {
        modifier(NeonTileModifier(accent: accent, state: state, shape: shape))
    }

    /// Glow an existing shape. Use when you've drawn a custom container
    /// and want it to participate in the elevation language.
    func neonGlow(_ accent: NeonAccent = .cyan, intensity: Double = SwooshNeonTokens.Glow.idle) -> some View {
        shadow(color: accent.color.opacity(intensity), radius: SwooshNeonTokens.Glow.radius)
    }
}

public enum NeonTileState: Sendable {
    case idle
    case focus
    case active

    var lineOpacity: Double {
        switch self {
        case .idle:   return SwooshNeonTokens.Line.dim
        case .focus, .active: return SwooshNeonTokens.Line.bright
        }
    }

    var glowIntensity: Double {
        switch self {
        case .idle:   return SwooshNeonTokens.Glow.idle
        case .focus:  return SwooshNeonTokens.Glow.focus
        case .active: return SwooshNeonTokens.Glow.active
        }
    }
}

public enum NeonTileShape: Sendable {
    case card
    case tile

    var radius: CGFloat {
        switch self {
        case .card: return SwooshNeonTokens.Radius.card
        case .tile: return SwooshNeonTokens.Radius.tile
        }
    }
}

private struct NeonTileModifier: ViewModifier {
    let accent: NeonAccent
    let state: NeonTileState
    let shape: NeonTileShape

    func body(content: Content) -> some View {
        let r = RoundedRectangle(cornerRadius: shape.radius, style: .continuous)
        return content
            .background(SwooshNeonTokens.Canvas.bg, in: r)
            .overlay(
                r.strokeBorder(
                    accent.color.opacity(state.lineOpacity),
                    lineWidth: SwooshNeonTokens.Line.width
                )
            )
            .shadow(
                color: accent.color.opacity(state.glowIntensity),
                radius: SwooshNeonTokens.Glow.radius
            )
    }
}
