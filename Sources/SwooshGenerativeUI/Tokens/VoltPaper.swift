// SwooshGenerativeUI/Tokens/VoltPaper.swift — 1.0 Volt Paper design system
//
// SwiftUI translation of the "Volt Paper" system (originally Tailwind/shadcn):
// warm paper / obsidian-purple-black canvas, inky typography, electric VIOLET
// for decisions (primary / selected / focus), acid LIME used SPARINGLY for
// live / active / success signals. Flat — borders + spacing + contrast, never
// heavy shadows, never glassmorphism, never gradients as primary styling.
//
// Colors are the spec's oklch values converted to sRGB. The app renders dark,
// so the dark (obsidian) palette is the canonical token set; light values are
// kept for a future light mode.

import SwiftUI

public enum VoltPaper {

    // ── Dark (obsidian) palette — the app's mode ────────────────────
    /// Obsidian purple-black. The canvas. Never pure black.
    public static let background = Color(.sRGB, red: 0.047, green: 0.042, blue: 0.108, opacity: 1)
    /// Card / panel — slightly lighter than the canvas, defined by border.
    public static let surface    = Color(.sRGB, red: 0.084, green: 0.079, blue: 0.159, opacity: 1)
    /// Warm near-white ink.
    public static let foreground = Color(.sRGB, red: 0.977, green: 0.944, blue: 0.891, opacity: 1)
    /// Quiet control fill (secondary / muted background).
    public static let muted      = Color(.sRGB, red: 0.147, green: 0.142, blue: 0.239, opacity: 1)
    /// Helper text, metadata, secondary labels.
    public static let mutedFg    = Color(.sRGB, red: 0.678, green: 0.625, blue: 0.554, opacity: 1)
    /// Electric violet — primary actions, selected, focus ring.
    public static let primary    = Color(.sRGB, red: 0.608, green: 0.550, blue: 1.000, opacity: 1)
    /// Ink on violet.
    public static let primaryFg  = Color(.sRGB, red: 0.039, green: 0.034, blue: 0.099, opacity: 1)
    /// Acid lime — live / active / success signal. Sparingly.
    public static let accent     = Color(.sRGB, red: 0.712, green: 1.000, blue: 0.017, opacity: 1)
    /// Ink on lime.
    public static let accentFg   = Color(.sRGB, red: 0.039, green: 0.034, blue: 0.099, opacity: 1)
    /// Errors / over-budget.
    public static let destructive = Color(.sRGB, red: 1.000, green: 0.335, blue: 0.342, opacity: 1)
    /// The primary structural device — flat borders, not shadows.
    public static let border     = Color(.sRGB, red: 0.189, green: 0.184, blue: 0.296, opacity: 1)

    /// Data-viz palette (the spec's chart tokens). The ONLY sanctioned source
    /// of multi-color categorisation — use instead of raw `Color.cyan/.pink/…`
    /// so category dots/badges stay on-brand rather than rainbow. chart1 is
    /// the dominant series; reach for chart3-5 only when data needs to pop.
    public enum Chart {
        public static let c1 = VoltPaper.primary                                            // violet
        public static let c2 = VoltPaper.accent                                             // lime
        public static let c3 = Color(.sRGB, red: 0.000, green: 0.807, blue: 0.894, opacity: 1) // cyan
        public static let c4 = Color(.sRGB, red: 1.000, green: 0.470, blue: 0.316, opacity: 1) // orange
        public static let c5 = Color(.sRGB, red: 0.885, green: 0.436, blue: 1.000, opacity: 1) // magenta
        public static let all: [Color] = [c1, c2, c3, c4, c5]
    }

    /// Stable categorical color — cycles the chart palette by index. Use for
    /// enum-keyed category/capability maps that need distinct-but-on-brand hues.
    public static func category(_ index: Int) -> Color {
        Chart.all[((index % Chart.all.count) + Chart.all.count) % Chart.all.count]
    }

    public enum Radius {
        public static let sm: CGFloat = 10
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 22
        public static let pill: CGFloat = 999
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Surfaces
// ═══════════════════════════════════════════════════════════════════

public extension View {
    /// Flat bordered card — `bg-card border`, no shadow. The standard panel.
    func voltCard(_ radius: CGFloat = VoltPaper.Radius.lg, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(VoltPaper.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(VoltPaper.border, lineWidth: 1))
    }

    /// Accent-rail card — a left lime rail for the one module that matters.
    func voltAccentRail(_ radius: CGFloat = VoltPaper.Radius.lg, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(VoltPaper.surface))
            .overlay(alignment: .leading) {
                Rectangle().fill(VoltPaper.accent).frame(width: 4)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(VoltPaper.border, lineWidth: 1))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Editorial section label (mono, uppercase, tracked)
// ═══════════════════════════════════════════════════════════════════

public struct VoltSectionLabel: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(VoltPaper.mutedFg)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Segmented selector (replaces stock Picker)
// ═══════════════════════════════════════════════════════════════════

/// Flat pill segmented control. Selected segment is violet-filled (a
/// decision). Replaces SwiftUI's default gray `Picker` chrome.
public struct VoltSegmented<Tag: Hashable>: View {
    public struct Option: Identifiable {
        public let label: String
        public let tag: Tag
        public var id: Tag { tag }
        public init(_ label: String, _ tag: Tag) { self.label = label; self.tag = tag }
    }

    let options: [Option]
    @Binding var selection: Tag

    public init(_ options: [Option], selection: Binding<Tag>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { opt in
                let isSel = opt.tag == selection
                Button {
                    selection = opt.tag
                } label: {
                    Text(opt.label)
                        .font(.system(size: 12, weight: isSel ? .bold : .medium))
                        .foregroundStyle(isSel ? VoltPaper.primaryFg : VoltPaper.mutedFg)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(isSel ? VoltPaper.primary : Color.clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(VoltPaper.muted))
        .overlay(Capsule().strokeBorder(VoltPaper.border, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Badges
// ═══════════════════════════════════════════════════════════════════

public struct VoltBadge: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(VoltPaper.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(VoltPaper.muted))
            .overlay(Capsule().strokeBorder(VoltPaper.border, lineWidth: 1))
    }
}

/// High-signal lime chip with a leading dot — for live / active states only.
public struct VoltLiveBadge: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(VoltPaper.accentFg).frame(width: 5, height: 5)
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(VoltPaper.accentFg)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(VoltPaper.accent))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Primary pill button
// ═══════════════════════════════════════════════════════════════════

public struct VoltPrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(VoltPaper.primaryFg)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Capsule().fill(VoltPaper.primary))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

public extension ButtonStyle where Self == VoltPrimaryButtonStyle {
    static var voltPrimary: VoltPrimaryButtonStyle { VoltPrimaryButtonStyle() }
}
