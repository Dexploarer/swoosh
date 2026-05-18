// SwooshUI/Themes/AppearanceControls.swift — Tabbed editor controls (0.4A)
//
// Each struct binds a slice of `SwooshThemeConfig`. Every visible setting on
// the theme surface has a control here — that's what "complete customization"
// means in this codebase. Controls are intentionally dense: column-aligned
// labels, monospaced numeric readouts, segmented pickers for enums.

import SwiftUI

// MARK: - Colors

struct ColorsControls: View {
    @Binding var config: SwooshThemeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Brand")
            colorRow("Accent",          path: \.colors.accent)
            colorRow("Secondary Accent", path: \.colors.secondaryAccent)

            sectionHeader("Surfaces")
            colorRow("Background",   path: \.colors.background)
            colorRow("Surface",      path: \.colors.surface)

            sectionHeader("Text")
            colorRow("Primary",   path: \.colors.textPrimary)
            colorRow("Secondary", path: \.colors.textSecondary)

            sectionHeader("Semantic")
            colorRow("Success", path: \.colors.success)
            colorRow("Warning", path: \.colors.warning)
            colorRow("Error",   path: \.colors.error)
            colorRow("Info",    path: \.colors.info)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }

    private func colorRow(_ label: String, path: WritableKeyPath<SwooshThemeConfig, String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 140, alignment: .leading)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(hex: config[keyPath: path]) },
                set: { newColor in
                    config[keyPath: path] = newColor.toHex() ?? config[keyPath: path]
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 40)

            Text(config[keyPath: path].uppercased())
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
        }
    }
}

// MARK: - Glass

struct GlassControls: View {
    @Binding var config: SwooshThemeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeled("Variant") {
                Picker("", selection: $config.glass.variant) {
                    Text("Regular").tag("regular")
                    Text("Clear").tag("clear")
                    Text("Identity").tag("identity")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            labeled("Shape") {
                Picker("", selection: $config.glass.shape) {
                    Text("Rounded").tag("roundedRect")
                    Text("Capsule").tag("capsule")
                    Text("Circle").tag("circle")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Interactive (responds to pointer)", isOn: $config.glass.interactive)
            Toggle("Union (group adjacent glass)",      isOn: $config.glass.enableUnion)
        }
    }
}

// MARK: - Layout

struct LayoutControls: View {
    @Binding var config: SwooshThemeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            slider("Corner Radius",  value: $config.layout.cornerRadius, range: 0...32, step: 1, unit: "pt")
            slider("Spacing",        value: $config.layout.spacing,      range: 4...32, step: 1, unit: "pt")
            slider("Padding",        value: $config.layout.padding,      range: 8...40, step: 1, unit: "pt")
            slider("Border Width",   value: $config.layout.borderWidth,  range: 0...2,  step: 0.25, unit: "pt")
        }
    }
}

// MARK: - Typography

struct TypographyControls: View {
    @Binding var config: SwooshThemeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            slider("Headline", value: $config.typography.headlineSize, range: 18...44, step: 1, unit: "pt")
            slider("Body",     value: $config.typography.bodySize,     range: 11...20, step: 1, unit: "pt")
            slider("Caption",  value: $config.typography.captionSize,  range: 9...16,  step: 1, unit: "pt")

            labeled("Font Design") {
                Picker("", selection: $config.typography.fontDesign) {
                    Text("Default").tag("default")
                    Text("Rounded").tag("rounded")
                    Text("Serif").tag("serif")
                    Text("Mono").tag("monospaced")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Monospaced code blocks", isOn: $config.typography.monospacedCode)
        }
    }
}

// MARK: - Animations

struct AnimationsControls: View {
    @Binding var config: SwooshThemeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            slider("Spring Duration",
                   value: $config.animations.springDuration,
                   range: 0.15...1.2, step: 0.05, unit: "s")
            slider("Spring Bounce",
                   value: $config.animations.springBounce,
                   range: 0...0.6, step: 0.05, unit: "")

            Toggle("Enable morphing (GlassEffectContainer)", isOn: $config.animations.enableMorphing)
            Toggle("Enable hover effects",                   isOn: $config.animations.enableHoverEffects)
        }
    }
}

// MARK: - Background

struct BackgroundControls: View {
    @Binding var config: SwooshThemeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeled("Kind") {
                Picker("", selection: $config.background.kind) {
                    Text("Solid").tag("solid")
                    Text("Mesh").tag("mesh")
                    Text("Animated").tag("meshAnimated")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Text("Fallback")
                    .font(.system(size: 12))
                    .frame(width: 140, alignment: .leading)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(hex: config.background.fallbackColor) },
                    set: { config.background.fallbackColor = $0.toHex() ?? config.background.fallbackColor }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 40)
                Text(config.background.fallbackColor.uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 70, alignment: .trailing)
            }

            if config.background.kind != "solid" {
                Text("Mesh Colors")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.top, 6)

                meshGrid

                if config.background.kind == "meshAnimated" {
                    slider("Animation Period",
                           value: $config.background.animationDuration,
                           range: 4...60, step: 1, unit: "s")
                }
            }

            HStack {
                Button("Randomize") { randomize() }
                    .controlSize(.small)
                Button("From Accent") { harmonizeFromAccent() }
                    .controlSize(.small)
                Spacer()
            }
        }
    }

    private var meshGrid: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { col in
                        let idx = row * 3 + col
                        ColorPicker("", selection: Binding(
                            get: { meshColor(at: idx) },
                            set: { setMeshColor(at: idx, $0) }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, minHeight: 28)
                    }
                }
            }
        }
    }

    private func meshColor(at idx: Int) -> Color {
        guard config.background.meshColors.indices.contains(idx) else { return .black }
        return Color(hex: config.background.meshColors[idx])
    }

    private func setMeshColor(at idx: Int, _ color: Color) {
        var colors = config.background.meshColors
        while colors.count <= idx { colors.append("#000000") }
        colors[idx] = color.toHex() ?? colors[idx]
        config.background.meshColors = colors
    }

    private func randomize() {
        let palette = (0..<9).map { _ -> String in
            let h = Double.random(in: 0...1)
            let s = Double.random(in: 0.3...0.9)
            let b = Double.random(in: 0.1...0.6)
            return Color(hue: h, saturation: s, brightness: b).toHex() ?? "#000000"
        }
        config.background.meshColors = palette
    }

    private func harmonizeFromAccent() {
        let accent = Color(hex: config.colors.accent)
        let surface = Color(hex: config.colors.surface)
        let background = Color(hex: config.colors.background)
        let bgHex = background.toHex() ?? "#000000"
        let surfHex = surface.toHex() ?? "#111111"
        let accHex = accent.toHex() ?? "#0066CC"
        config.background.meshColors = [
            bgHex, surfHex, bgHex,
            surfHex, accHex, surfHex,
            bgHex, surfHex, bgHex,
        ]
    }
}

// MARK: - Shared builders

private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
        content()
    }
}

private func slider(_ label: String,
                    value: Binding<CGFloat>,
                    range: ClosedRange<CGFloat>,
                    step: CGFloat,
                    unit: String) -> some View {
    HStack {
        Text(label)
            .font(.system(size: 12))
            .frame(width: 120, alignment: .leading)
        Slider(value: value, in: range, step: step)
        Text(formatted(value.wrappedValue, unit: unit))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 52, alignment: .trailing)
    }
}

private func slider(_ label: String,
                    value: Binding<Double>,
                    range: ClosedRange<Double>,
                    step: Double,
                    unit: String) -> some View {
    HStack {
        Text(label)
            .font(.system(size: 12))
            .frame(width: 120, alignment: .leading)
        Slider(value: value, in: range, step: step)
        Text(String(format: unit.isEmpty ? "%.2f" : "%.2f\(unit)", value.wrappedValue))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 56, alignment: .trailing)
    }
}

private func formatted(_ v: CGFloat, unit: String) -> String {
    let intish = v == v.rounded()
    if intish { return "\(Int(v))\(unit)" }
    return String(format: "%.2f%@", Double(v), unit)
}

// MARK: - Color → hex bridge

extension Color {
    /// Convert to a `#RRGGBB` string. Returns nil if the platform can't resolve
    /// the color components (some system colors aren't sRGB-resolvable).
    func toHex() -> String? {
        #if canImport(AppKit)
        let resolved = NSColor(self).usingColorSpace(.sRGB)
        guard let c = resolved else { return nil }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
        #elseif canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X",
                      clamp(Int((r * 255).rounded())),
                      clamp(Int((g * 255).rounded())),
                      clamp(Int((b * 255).rounded())))
        #else
        return nil
        #endif
    }
}

private func clamp(_ v: Int) -> Int { max(0, min(255, v)) }

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
