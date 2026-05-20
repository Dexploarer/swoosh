// Apps/SwooshiOS/ProviderLogo.swift — Visual marks for model providers
//
// Initial-tile + tint per known provider. The visual identifies each
// provider at a glance without bundling third-party brand assets — the
// tile colors map to the provider's commonly-associated palette, and the
// initials are computed from the provider name.

import SwiftUI

struct ProviderLogo: View {
    let providerID: String
    let providerName: String
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10

    var body: some View {
        InitialsTile(
            text: initials,
            background: background,
            foreground: foreground,
            size: size,
            cornerRadius: cornerRadius
        )
    }

    private var initials: String {
        switch providerID {
        case "openai":           return "OA"
        case "openrouter":       return "OR"
        case "eliza-cloud":      return "EZ"
        case "local-openai":     return "LO"
        case "local-diagnostic": return "LD"
        case "anthropic":        return "A"
        case "google":           return "G"
        case "groq":             return "Gq"
        case "perplexity":       return "Px"
        default:
            let trimmed = providerName.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ").prefix(2)
            if parts.count == 2 {
                return String(parts.map { $0.first ?? Character(" ") })
            }
            return String(trimmed.prefix(2)).uppercased()
        }
    }

    private var background: Color {
        switch providerID {
        case "openai":           return Color(red: 0.06, green: 0.06, blue: 0.06)
        case "openrouter":       return Color(red: 0.34, green: 0.36, blue: 0.95)
        case "eliza-cloud":      return Color(red: 0.18, green: 0.65, blue: 0.55)
        case "local-openai":     return Color(red: 0.32, green: 0.38, blue: 0.46)
        case "local-diagnostic": return Color(red: 0.42, green: 0.42, blue: 0.48)
        case "anthropic":        return Color(red: 0.84, green: 0.50, blue: 0.32)
        case "google":           return Color(red: 0.92, green: 0.32, blue: 0.27)
        case "groq":             return Color(red: 0.96, green: 0.43, blue: 0.27)
        case "perplexity":       return Color(red: 0.10, green: 0.55, blue: 0.62)
        default:                 return Color(red: 0.30, green: 0.30, blue: 0.36)
        }
    }

    private var foreground: Color { .white }
}
