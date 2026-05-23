// SwooshGenerativeUI/BuiltinStyling.swift — Shared built-in renderer styling (0.4A)

import SwiftUI

struct RGBColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

@MainActor
func resolveTint(_ token: String?) -> Color {
    guard let token else { return .accentColor }
    switch token.lowercased() {
    case "accent": return .accentColor
    case "primary": return .primary
    case "secondary": return .secondary
    case "success": return .green
    case "warning": return .yellow
    case "error": return .red
    case "info": return .blue
    default:
        guard token.hasPrefix("#") else { return .accentColor }
        return hexColor(token)
    }
}

func parseHexColor(_ hex: String) -> RGBColor? {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = if trimmed.hasPrefix("#") {
        String(trimmed.dropFirst())
    } else {
        trimmed
    }
    guard cleaned.count == 3 || cleaned.count == 6 else { return nil }
    guard cleaned.allSatisfy(\.isHexDigit) else { return nil }
    var int: UInt64 = 0
    guard Scanner(string: cleaned).scanHexInt64(&int) else { return nil }
    let r: UInt64
    let g: UInt64
    let b: UInt64
    switch cleaned.count {
    case 6:
        r = int >> 16
        g = int >> 8 & 0xFF
        b = int & 0xFF
    case 3:
        r = (int >> 8) * 17
        g = (int >> 4 & 0xF) * 17
        b = (int & 0xF) * 17
    default:
        return nil
    }
    return RGBColor(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
}

func hexColor(_ hex: String) -> Color {
    guard let rgb = parseHexColor(hex) else { return .accentColor }
    return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
}

@MainActor
func resolveFontDesign(_ token: String?) -> Font.Design {
    switch token {
    case "rounded": return .rounded
    case "serif": return .serif
    case "monospaced": return .monospaced
    default: return .default
    }
}

@MainActor
func resolveFontWeight(_ token: String?) -> Font.Weight {
    switch token {
    case "medium": return .medium
    case "semibold": return .semibold
    case "bold": return .bold
    case "heavy": return .heavy
    case "light": return .light
    default: return .regular
    }
}

extension View {
    @ViewBuilder
    func applyStyle(_ style: UIStyle?) -> some View {
        if let style {
            modifier(UIStyleModifier(style: style))
        } else {
            self
        }
    }
}

struct UIStyleModifier: ViewModifier {
    let style: UIStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        styled(content)
    }

    @ViewBuilder
    private func styled(_ content: Content) -> some View {
        if let r = style.cornerRadius {
            padded(content)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(r), style: .continuous))
        } else {
            padded(content)
        }
    }

    @ViewBuilder
    private func padded(_ content: Content) -> some View {
        if let pad = style.padding {
            content.padding(CGFloat(pad))
        } else {
            content
        }
    }
}
